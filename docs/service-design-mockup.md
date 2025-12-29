# PAGI::OpenAPI Service Design

> **Status: IMPLEMENTED** - This design has been implemented in PAGI::OpenAPI.
> See the examples in `examples/` and the POD documentation for usage.

## Design Principles

1. **Functions first, classes optional** - Simple cases should be simple
2. **Return type determines scope** - Object = app-scoped, Coderef = request-scoped
3. **Explicit cleanup hooks** - `$app->on_shutdown`, `$c->on_request_end`
4. **Visible dependencies** - Easy to trace what depends on what
5. **Lazy resolution** - Services created on first access

---

## Core API

### The `service()` Method

A single registration method with scope determined by return type:

```perl
$self->service(name => sub {
    my ($app) = @_;

    # Return object → app-scoped (singleton)
    # Return coderef → request-scoped (called per request)
});
```

---

## App-Scoped Services (Singletons)

Return an object directly for app-scoped services:

```perl
sub setup_services {
    my ($self) = @_;

    # Simple config - returns hashref, created once
    $self->service(config => sub {
        my ($app) = @_;
        return {
            jwt_secret => $ENV{JWT_SECRET},
            max_todos  => 1000,
        };
    });

    # Database pool - app-scoped, lives for app lifetime
    $self->service(db => sub {
        my ($app) = @_;
        my $db = DBI->connect($ENV{DATABASE_URL});

        # Register cleanup for app shutdown
        $app->on_shutdown(sub { $db->disconnect });

        return $db;
    });

    # Redis connection - depends on config
    $self->service(redis => sub {
        my ($app) = @_;
        my $redis = Redis->new(
            server => $app->service('config')->{redis_url}
        );

        $app->on_shutdown(sub { $redis->quit });

        return $redis;
    });
}
```

---

## Request-Scoped Services

Return a coderef for request-scoped services. The coderef receives `($c, @args)`:

```perl
sub setup_services {
    my ($self) = @_;

    # Current user - different per request
    $self->service(current_user => sub {
        my ($app) = @_;
        return sub {
            my ($c) = @_;
            my $token = $c->bearer_token or return;
            return decode_jwt($token, $app->service('config')->{jwt_secret});
        };
    });

    # Transaction wrapper - request-scoped with cleanup
    $self->service(transaction => sub {
        my ($app) = @_;
        return sub {
            my ($c) = @_;
            my $tx = $app->service('db')->begin_work;

            # Auto-rollback if not committed
            $c->on_request_end(sub {
                $tx->rollback if $tx->active;
            });

            return $tx;
        };
    });

    # Todo service - request-scoped, uses app-scoped db
    $self->service(todos => sub {
        my ($app) = @_;
        return sub {
            my ($c) = @_;
            return TodoService->new(
                db   => $app->service('db'),
                user => $c->current_user,
            );
        };
    });
}
```

---

## Service Access with Arguments

The inner coderef can accept additional arguments:

```perl
# Registration
$self->service(logger => sub {
    my ($app) = @_;
    return sub {
        my ($c, $category) = @_;
        $category //= 'default';
        return Logger->new(
            category   => $category,
            request_id => $c->request_id,
        );
    };
});

# Usage in handlers
my $logger = $c->logger('auth');  # Passes 'auth' as $category
$logger->info("User logged in");
```

---

## Handler Usage

Services are accessed directly on `$c`:

```perl
package MyAPI::Handlers::Todos;
use parent 'PAGI::OpenAPI::Handler';
use Future::AsyncAwait;

async sub list {
    my ($self, $c) = @_;

    # Direct service access
    my $todos = $c->todos->list(
        limit => $c->query('limit') // 20,
    );

    await $c->json({ todos => $todos });
}

async sub create {
    my ($self, $c) = @_;

    # Auth check via request-scoped service
    return await $c->unauthorized unless $c->current_user;

    my $data = await $c->request_json;
    my $todo = $c->todos->create($data);

    await $c->status(201)->json($todo);
}
```

---

## Scope Summary

| Return Type | Scope | Created | Cached | Cleanup |
|-------------|-------|---------|--------|---------|
| Object/Value | App | First access | Forever | `$app->on_shutdown` |
| Coderef | Request | Each request | Per request | `$c->on_request_end` |

---

## Full Example

```perl
package BookstoreAPI;
use parent 'PAGI::OpenAPI';
use Future::AsyncAwait;

sub openapi_schema { 'schema.yaml' }

sub setup_services {
    my ($self) = @_;

    # ========================================
    # App-scoped (return objects)
    # ========================================

    $self->service(config => sub {
        my ($app) = @_;
        return {
            db_dsn     => $ENV{DATABASE_URL},
            jwt_secret => $ENV{JWT_SECRET},
            redis_url  => $ENV{REDIS_URL} // 'localhost:6379',
        };
    });

    $self->service(db => sub {
        my ($app) = @_;
        my $db = DBI->connect($app->service('config')->{db_dsn});
        $app->on_shutdown(sub { $db->disconnect });
        return $db;
    });

    $self->service(redis => sub {
        my ($app) = @_;
        my $redis = Redis->new(server => $app->service('config')->{redis_url});
        $app->on_shutdown(sub { $redis->quit });
        return $redis;
    });

    # ========================================
    # Request-scoped (return coderefs)
    # ========================================

    $self->service(current_user => sub {
        my ($app) = @_;
        return sub {
            my ($c) = @_;
            my $token = $c->bearer_token or return;
            return decode_jwt($token, $app->service('config')->{jwt_secret});
        };
    });

    $self->service(books => sub {
        my ($app) = @_;
        return sub {
            my ($c) = @_;
            return BookstoreAPI::Service::Books->new(
                db    => $app->service('db'),
                cache => $app->service('redis'),
            );
        };
    });

    $self->service(reviews => sub {
        my ($app) = @_;
        return sub {
            my ($c) = @_;
            return BookstoreAPI::Service::Reviews->new(
                db   => $app->service('db'),
                user => $c->current_user,
            );
        };
    });
}

async sub on_startup {
    my ($self, $scope) = @_;
    print "Bookstore API started!\n";
}

1;
```

---

## Implementation Sketch

### PAGI::OpenAPI additions

```perl
sub service {
    my ($self, $name, $factory) = @_;
    $self->{_services}{$name} = {
        factory  => $factory,
        instance => undef,  # For app-scoped caching
    };
}

# For $app->service('name') access
sub _get_service {
    my ($self, $name) = @_;
    my $svc = $self->{_services}{$name}
        or croak "Unknown service: $name";

    # Lazy creation
    if (!defined $svc->{instance}) {
        my $result = $svc->{factory}->($self);

        # If coderef returned, this is request-scoped
        # Store the factory coderef, not the result
        if (ref($result) eq 'CODE') {
            $svc->{is_request_scoped} = 1;
            $svc->{request_factory} = $result;
        } else {
            # App-scoped: cache the instance
            $svc->{instance} = $result;
        }
    }

    return $svc->{instance};  # Returns undef for request-scoped
}

# Shutdown cleanup
sub _shutdown_cleanups {
    my ($self) = @_;
    for my $cb (@{$self->{_shutdown_callbacks} // []}) {
        eval { $cb->() };
        warn "Shutdown cleanup error: $@" if $@;
    }
}

sub on_shutdown {
    my ($self, $cb) = @_;
    push @{$self->{_shutdown_callbacks}}, $cb;
}
```

### PAGI::OpenAPI::Context additions

```perl
sub AUTOLOAD {
    my $self = shift;
    my @args = @_;
    my ($name) = our $AUTOLOAD =~ /::(\w+)$/;
    return if $name eq 'DESTROY';

    my $svc = $self->app->{_services}{$name}
        or croak "Unknown service: $name";

    # Ensure factory has been called
    $self->app->_get_service($name) unless defined $svc->{instance}
                                       || $svc->{is_request_scoped};

    if ($svc->{is_request_scoped}) {
        # Request-scoped: check cache first
        my $key = "_svc_$name";
        return $self->stash->{$key} if exists $self->stash->{$key} && !@args;

        # Create new instance
        my $instance = $svc->{request_factory}->($self, @args);

        # Cache if no args (stateless access)
        $self->stash->{$key} = $instance unless @args;

        return $instance;
    } else {
        # App-scoped: return cached instance
        return $svc->{instance};
    }
}

sub on_request_end {
    my ($self, $cb) = @_;
    push @{$self->stash->{_request_end_callbacks}}, $cb;
}

# Called by framework after response sent
sub _run_request_end_callbacks {
    my ($self) = @_;
    for my $cb (@{$self->stash->{_request_end_callbacks} // []}) {
        eval { $cb->() };
        warn "Request end cleanup error: $@" if $@;
    }
}
```

---

## Key Differences from PAGI-Simple

| Aspect | PAGI-Simple | This Design |
|--------|-------------|-------------|
| Scope definition | Class inheritance | Return type |
| Service access | `$c->service('Name')` | `$c->name` (AUTOLOAD) |
| App-scoped access | N/A in handler | `$app->service('name')` in factory |
| Cleanup | `on_request_end` method | `$app->on_shutdown`, `$c->on_request_end` |
| Dependencies | Manual in constructor | Via `$app` in factory |
| Simple singletons | Full class needed | Return value directly |
| Class requirement | Must extend base class | Plain Perl classes |

---

## Design Decisions

1. **Return type determines scope** - Simpler than explicit `scope =>` parameter. Objects are naturally "ready to use" (app-scoped), coderefs naturally "need to be called" (request-scoped).

2. **Factory receives `$app`, not `$c`** - Ensures app-scoped services can't accidentally depend on request-scoped data.

3. **Lazy resolution** - Services created on first access, not at registration time.

4. **Request caching by default** - Request-scoped services cached per request unless called with arguments.

5. **Explicit cleanup hooks** - `$app->on_shutdown` and `$c->on_request_end` are clearer than generator patterns.

---

## Open Questions

1. **Async factories?** Should service factories support async/await?
   ```perl
   $self->service(db => async sub {
       my ($app) = @_;
       return await IO::Async::DBI->connect(...);
   });
   ```

2. **Validation?** Should we warn if app-scoped service tries to access request-scoped?

3. **Testing support?** Should there be a way to mock services in tests?
   ```perl
   $app->mock_service(db => $mock_db);
   ```
