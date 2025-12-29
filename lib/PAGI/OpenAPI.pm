package PAGI::OpenAPI;

use strict;
use warnings;
use parent 'PAGI::Endpoint::Router';
use Future::AsyncAwait;
use Module::Load qw(load);
use Carp qw(croak);
use Scalar::Util qw(blessed);
use JSON::MaybeXS qw(encode_json);
use Path::Tiny qw(path);

# ============================================================
# Configuration methods - override in subclass
# ============================================================

# Path to OpenAPI schema file (YAML or JSON)
sub openapi_schema { undef }

# Namespace for handler classes
sub handler_namespace {
    my $self = shift;
    my $class = ref($self) || $self;
    return "${class}::Handlers";
}

# Enable Swagger UI at /docs
sub enable_docs { 1 }

# Enable request validation
sub enable_validation { 1 }

# Separator in operationId (Handler.method)
sub operation_separator { '.' }

# Service registration - override in subclass
sub setup_services {
    my ($self) = @_;
    # $self->service(name => sub { ... });
}

# Lifespan hooks - override in subclass
async sub on_startup {
    my ($self, $scope) = @_;
}

async sub on_shutdown {
    my ($self, $scope) = @_;
}

# Simple routes - override in subclass
sub setup_routes {
    my ($self, $r) = @_;
    # $r->get('/health' => sub { ... });
}

# ============================================================
# Script Runner (Web::Simple style)
# ============================================================

# Middleware stack - override in subclass
# Return list of middleware specs:
#   'PAGI::Middleware::AccessLog'                    # Just class name
#   ['PAGI::Middleware::CORS', origins => ['*']]     # Class + args
#   sub { my $app = shift; ... }                     # Coderef wrapper
sub middleware {
    return ();  # No middleware by default
}

# Call at end of your app module to make it runnable:
#   __PACKAGE__->run_if_script;
#
# Returns the app (with middleware) for pagi-server to use
sub run_if_script {
    my $class = shift;

    # Build the app with middleware
    my $self = ref($class) ? $class : $class->new;
    my $app = $self->to_app;

    # Apply middleware if any
    $app = $self->_apply_middleware($app);

    return $app;
}

sub _apply_middleware {
    my ($self, $app) = @_;

    my @middleware = $self->middleware;
    return $app unless @middleware;

    # Apply middleware in reverse order (first in list wraps outermost)
    for my $mw (reverse @middleware) {
        if (ref($mw) eq 'CODE') {
            # Coderef: call directly
            $app = $mw->($app);
        }
        elsif (ref($mw) eq 'ARRAY') {
            # Arrayref: [class, args...]
            my ($mw_class, @args) = @$mw;
            load($mw_class);
            $app = $mw_class->new(@args)->wrap($app);
        }
        else {
            # String: just class name
            load($mw);
            $app = $mw->new->wrap($app);
        }
    }

    return $app;
}

# ============================================================
# Home Directory
# ============================================================

# Class-level cache for home directories (keyed by class name)
my %_home_cache;

# Get the application's home directory as a Path::Tiny object
# Works as both class method and instance method.
# Detection order:
#   1. PAGI_HOME environment variable (always checked, never cached)
#   2. Auto-detect from app class location (strips lib/ or blib/)
#   3. Fallback to current working directory
sub home {
    my $self = shift;
    my $class = ref($self) || $self;

    # 1. Environment variable override (always takes priority, not cached)
    if ($ENV{PAGI_HOME}) {
        return path($ENV{PAGI_HOME})->absolute;
    }

    # Check instance cache (if called on object)
    return $self->{_home} if ref($self) && $self->{_home};

    # Check class-level cache
    return $_home_cache{$class} if $_home_cache{$class};

    my $home;

    # 2. Auto-detect from app class location
    (my $file = "$class.pm") =~ s{::}{/}g;

    # Try direct lookup first (works when loaded via 'use')
    my $inc_path = $INC{$file};

    # If not found, search %INC values (works when loaded via 'do')
    # This handles pagi-server loading via: do '/path/to/MyApp.pm'
    if (!$inc_path) {
        for my $key (keys %INC) {
            if ($key =~ /\Q$file\E$/ || $INC{$key} =~ /\Q$file\E$/) {
                $inc_path = $INC{$key};
                last;
            }
        }
    }

    if ($inc_path) {
        $home = path($inc_path)->absolute->parent;

        # Walk up and strip lib/ or blib/ directories
        # e.g., /app/lib/MyAPI.pm -> /app/lib -> /app
        #       /app/blib/lib/MyAPI.pm -> /app/blib/lib -> /app/blib -> /app
        while ($home->basename =~ /^(?:lib|blib)$/i && !$home->is_rootdir) {
            $home = $home->parent;
        }
    }
    else {
        # 3. Fallback to current working directory
        $home = path('.')->absolute;
    }

    # Cache at both levels
    $_home_cache{$class} = $home;
    $self->{_home} = $home if ref($self);

    return $home;
}

# Convenience: get a path relative to home
# Returns a Path::Tiny object
sub home_path {
    my ($self, @parts) = @_;
    return $self->home->child(@parts);
}

# ============================================================
# Service Registration and Resolution
# ============================================================

# Register or get a service
# With 2 args (name, factory): register a service
#   - Return object/value from factory -> app-scoped (singleton)
#   - Return coderef from factory -> request-scoped (called per request with $c)
# With 1 arg (name): get a service (for use in service factories)
sub service {
    my $self = shift;

    if (@_ == 1) {
        # Get a service by name
        my ($name) = @_;
        return $self->_get_service($name);
    }

    # Register a service
    my ($name, $factory) = @_;

    croak "Service name required" unless defined $name;
    croak "Service factory required" unless ref($factory) eq 'CODE';

    $self->{_services}{$name} = {
        factory          => $factory,
        instance         => undef,
        is_request_scoped => undef,  # Determined on first resolution
        request_factory  => undef,
    };
}

# Get an app-scoped service instance (for use in factories)
# Returns undef for request-scoped services
# This is a private method; use the public service() method for lookup
sub _get_service {
    my ($self, $name) = @_;

    my $svc = $self->{_services}{$name}
        or croak "Unknown service: $name";

    # Already resolved
    return $svc->{instance} if defined $svc->{instance};
    return undef if $svc->{is_request_scoped};

    # First-time resolution: call factory to determine scope
    my $result = $svc->{factory}->($self);

    if (ref($result) eq 'CODE') {
        # Returns coderef -> request-scoped
        $svc->{is_request_scoped} = 1;
        $svc->{request_factory} = $result;
        return undef;
    } else {
        # Returns value -> app-scoped (cache it)
        $svc->{is_request_scoped} = 0;
        $svc->{instance} = $result;
        return $result;
    }
}


# Register a shutdown callback (for app-scoped service cleanup)
sub add_shutdown_callback {
    my ($self, $cb) = @_;
    push @{$self->{_shutdown_callbacks}}, $cb;
}

# Run all shutdown callbacks
sub _run_shutdown_callbacks {
    my ($self) = @_;
    for my $cb (@{$self->{_shutdown_callbacks} // []}) {
        eval { $cb->() };
        warn "Shutdown cleanup error: $@" if $@;
    }
}

# ============================================================
# Route building
# ============================================================

sub routes {
    my ($self, $r) = @_;

    # Initialize services hash
    $self->{_services} //= {};

    # Let subclass register services
    $self->setup_services;

    # Let subclass define simple routes first
    $self->setup_routes($r);

    # Load OpenAPI schema if defined
    my $schema_file = $self->openapi_schema;
    return unless $schema_file;

    my $schema = $self->_load_schema($schema_file);
    $self->state->{_openapi_schema} = $schema;

    # Build OpenAPI::Modern validator
    if ($self->enable_validation) {
        $self->state->{_openapi} = $self->_build_validator($schema, $schema_file);
    }

    # Initialize handler cache
    $self->state->{_handlers} = {};

    # Schema endpoints
    $r->get('/openapi.json' => 'serve_openapi_json');
    $r->get('/openapi.yaml' => 'serve_openapi_yaml');

    if ($self->enable_docs) {
        $r->get('/docs' => 'serve_docs');
    }

    # Wire OpenAPI operations to handlers
    $self->_wire_operations($r, $schema);
}

# ============================================================
# Built-in handlers for schema endpoints
# ============================================================

async sub serve_openapi_json {
    my ($self, $req, $res) = @_;
    my $schema = $self->state->{_openapi_schema};
    await $res
        ->header('Cache-Control' => 'public, max-age=3600')
        ->header('Access-Control-Allow-Origin' => '*')
        ->json($schema);
}

async sub serve_openapi_yaml {
    my ($self, $req, $res) = @_;
    require YAML::PP;
    my $schema = $self->state->{_openapi_schema};
    my $yaml = YAML::PP->new(boolean => 'JSON::PP')->dump_string($schema);
    await $res
        ->content_type('application/yaml; charset=utf-8')
        ->header('Cache-Control' => 'public, max-age=3600')
        ->header('Access-Control-Allow-Origin' => '*')
        ->send($yaml);
}

async sub serve_docs {
    my ($self, $req, $res) = @_;
    my $html = $self->_swagger_ui_html;
    await $res->html($html);
}

# ============================================================
# Schema loading
# ============================================================

sub _load_schema {
    my ($self, $file) = @_;

    # Resolve relative paths against home directory
    my $schema_path = path($file);
    unless ($schema_path->is_absolute) {
        $schema_path = $self->home->child($file);
    }

    croak "Schema file not found: $schema_path" unless $schema_path->is_file;

    $file = $schema_path->stringify;

    if ($file =~ /\.ya?ml$/i) {
        require YAML::PP;
        return YAML::PP->new(boolean => 'JSON::PP')->load_file($file);
    }
    elsif ($file =~ /\.json$/i) {
        require JSON::MaybeXS;
        open my $fh, '<:encoding(UTF-8)', $file or croak "Cannot open $file: $!";
        local $/;
        return JSON::MaybeXS::decode_json(<$fh>);
    }
    else {
        croak "Unknown schema format: $file (expected .yaml, .yml, or .json)";
    }
}

sub _build_validator {
    my ($self, $schema, $schema_file) = @_;

    require OpenAPI::Modern;
    require URI;

    # Create URI for schema
    my $uri = URI->new("file://$schema_file");

    return OpenAPI::Modern->new(
        openapi_uri    => $uri->as_string,
        openapi_schema => $schema,
    );
}

# ============================================================
# Operation wiring
# ============================================================

sub _wire_operations {
    my ($self, $r, $schema) = @_;

    my $paths = $schema->{paths} // {};

    for my $path (sort keys %$paths) {
        my $path_item = $paths->{$path};

        for my $method (qw(get post put patch delete head options)) {
            my $op = $path_item->{$method} or next;
            my $op_id = $op->{operationId} or next;

            # Parse operationId: "Todos.list" -> ("Todos", "list")
            my ($handler_name, $method_name) = $self->_parse_operation_id($op_id);

            # Convert OpenAPI path to PAGI router path: {id} -> :id
            my $pagi_path = $path;
            $pagi_path =~ s/\{(\w+)\}/:$1/g;

            # Build wrapped handler
            my $handler = $self->_build_handler(
                handler_name  => $handler_name,
                method_name   => $method_name,
                path_template => $path,
                http_method   => $method,
                operation     => $op,
            );

            # Register route with operationId as name
            $r->$method($pagi_path => $handler)->name($op_id);
        }
    }
}

sub _parse_operation_id {
    my ($self, $op_id) = @_;

    my $sep = quotemeta($self->operation_separator);

    if ($op_id =~ /^(\w+)${sep}(\w+)$/) {
        return ($1, $2);
    }

    # No namespace - use Default handler, convert camelCase to snake_case
    my $method_name = $op_id;
    $method_name =~ s/([a-z])([A-Z])/${1}_\L$2/g;
    $method_name = lc($method_name);

    return ('Default', $method_name);
}

sub _build_handler {
    my ($self, %args) = @_;

    my $handler_name  = $args{handler_name};
    my $method_name   = $args{method_name};
    my $path_template = $args{path_template};
    my $http_method   = $args{http_method};

    # Capture $self for closure
    my $app = $self;

    # Return handler that receives ($req, $res) from router wrapper
    return async sub {
        my ($req, $res) = @_;

        # Get scope from request for context and validation
        my $scope = $req->{scope};

        # Create context with request/response objects
        require PAGI::OpenAPI::Context;
        my $c = PAGI::OpenAPI::Context->new(
            app           => $app,
            scope         => $scope,
            receive       => $req->{receive},
            send          => $res->{send},
            services      => $app->{_services},
            path_template => $path_template,
            http_method   => $http_method,
            _req          => $req,  # Reuse existing request object
            _res          => $res,  # Reuse existing response object
        );

        # Validate request if enabled
        if ($app->enable_validation && $app->state->{_openapi}) {
            # Buffer body for validation (if there's content)
            if ($c->req->content_length) {
                await $c->body;
            }

            require PAGI::OpenAPI::Bridge;
            my $result = PAGI::OpenAPI::Bridge->validate_request(
                $app->state->{_openapi},
                $scope,
                path_template => $path_template,
                path_captures => $scope->{path_params},
                method        => $http_method,
            );

            if (!$result->valid) {
                $c->_run_request_end_callbacks;
                return await $c->status(400)->json({
                    error   => 'Request validation failed',
                    details => $result->TO_JSON,
                });
            }
        }

        # Get handler instance
        my $handler = eval { $app->_get_handler($handler_name) };
        if ($@) {
            my $error = $@;
            warn "Handler loading error: $error";
            $c->_run_request_end_callbacks;
            return await $c->status(500)->json({
                error   => 'Internal server error',
                message => ($ENV{PAGI_ENV} // '') eq 'development' ? "$error" : undef,
            });
        }

        # Call method
        my $code = $handler->can($method_name);
        unless ($code) {
            my $msg = "No method '$method_name' in " . ref($handler)
                    . " (for operationId: $handler_name.$method_name)";
            warn $msg;
            $c->_run_request_end_callbacks;
            return await $c->status(500)->json({
                error   => 'Internal server error',
                message => ($ENV{PAGI_ENV} // '') eq 'development' ? $msg : undef,
            });
        }

        my $result = eval { await $handler->$code($c) };
        my $error = $@;

        # Always run request-end callbacks
        $c->_run_request_end_callbacks;

        # If handler threw an error and no response was sent, return 500
        if ($error) {
            warn "Handler error: $error";
            # Check if response was already started
            if (!$c->{_response_started}) {
                return await $c->status(500)->json({
                    error   => 'Internal server error',
                    message => ($ENV{PAGI_ENV} // '') eq 'development' ? "$error" : undef,
                });
            }
            # Response already started, can't send error response
            die $error;
        }

        return $result;
    };
}

sub _get_handler {
    my ($self, $name) = @_;

    # Return cached instance
    return $self->state->{_handlers}{$name}
        if $self->state->{_handlers}{$name};

    # Build class name
    my $class = $self->handler_namespace . '::' . $name;

    # Load class if not already loaded (check for ->can('new'))
    unless ($class->can('new')) {
        load($class);
    }

    my $instance = $class->new(app => $self);
    $self->state->{_handlers}{$name} = $instance;

    return $instance;
}


# ============================================================
# Swagger UI HTML
# ============================================================

sub _swagger_ui_html {
    my $self = shift;

    return <<"HTML";
<!DOCTYPE html>
<html>
<head>
    <title>API Documentation</title>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist\@5/swagger-ui.css">
    <style>
        body { margin: 0; padding: 0; }
        .swagger-ui .topbar { display: none; }
    </style>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist\@5/swagger-ui-bundle.js"></script>
    <script>
        window.onload = function() {
            SwaggerUIBundle({
                url: "./openapi.json",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis
                ]
            });
        };
    </script>
</body>
</html>
HTML
}

# ============================================================
# Lifespan integration
# ============================================================

sub to_app {
    my ($class) = @_;

    # Create single instance for app lifetime
    my $instance = blessed($class) ? $class : $class->new;

    # Build internal router (same as Endpoint::Router::to_app but we control instance)
    load('PAGI::App::Router');
    my $internal_router = PAGI::App::Router->new;

    # Let subclass define routes (this also calls setup_services)
    $instance->_build_routes($internal_router);

    # Store router reference for uri_for access
    $instance->{_router} = $internal_router;

    my $router_app = $internal_router->to_app;

    # Capture any state set during route building (schema, handlers cache, etc.)
    my $route_state = $instance->{_state} // {};

    # Create the base app - don't inject state here, let Lifespan handle it
    my $base_app = async sub {
        my ($scope, $receive, $send) = @_;

        # Dispatch to internal router
        await $router_app->($scope, $receive, $send);
    };

    # Wrap with lifespan handling
    require PAGI::Lifespan;

    return PAGI::Lifespan->wrap(
        $base_app,
        startup => async sub {
            my ($lifespan_state) = @_;
            # Copy route-building state to lifespan state
            # This preserves _openapi_schema, _openapi, _handlers, etc.
            for my $key (keys %$route_state) {
                $lifespan_state->{$key} = $route_state->{$key};
            }
            # Point instance to lifespan state
            $instance->{_state} = $lifespan_state;
            await $instance->on_startup({ type => 'lifespan', state => $lifespan_state });
        },
        shutdown => async sub {
            my ($lifespan_state) = @_;
            # Run service shutdown callbacks first
            $instance->_run_shutdown_callbacks();
            # Then call user's on_shutdown hook
            await $instance->on_shutdown({ type => 'lifespan', state => $lifespan_state });
        },
    );
}

1;

__END__

=head1 NAME

PAGI::OpenAPI - Schema-first OpenAPI framework for PAGI

=head1 SYNOPSIS

    package MyAPI;
    use parent 'PAGI::OpenAPI';
    use Future::AsyncAwait;

    sub openapi_schema { 'schemas/openapi.yaml' }

    # Service registration - return type determines scope
    sub setup_services {
        my ($self) = @_;

        # App-scoped: returns object (persists across requests)
        $self->service(config => sub {
            my ($app) = @_;
            return { jwt_secret => $ENV{JWT_SECRET} };
        });

        # App-scoped: database connection
        $self->service(db => sub {
            my ($app) = @_;
            my $db = DBI->connect($ENV{DATABASE_URL});
            # Register cleanup for shutdown
            $app->add_shutdown_callback(sub { $db->disconnect });
            return $db;
        });

        # Request-scoped: returns coderef (new per request)
        $self->service(current_user => sub {
            my ($app) = @_;
            return sub {
                my ($c) = @_;
                my $token = $c->bearer_token or return;
                return decode_jwt($token, $app->service('config')->{jwt_secret});
            };
        });
    }

    async sub on_startup {
        my ($self, $scope) = @_;
        print "API started!\n";
    }

    1;

Then create handler classes:

    package MyAPI::Handlers::Todos;
    use parent 'PAGI::OpenAPI::Handler';
    use Future::AsyncAwait;

    async sub list {
        my ($self, $c) = @_;
        my $todos = $c->db->selectall_arrayref('SELECT * FROM todos');
        await $c->json({ todos => $todos });
    }

    async sub create {
        my ($self, $c) = @_;
        return await $c->unauthorized unless $c->current_user;
        my $data = await $c->request_json;
        # ...
    }

    1;

With an OpenAPI schema:

    # schemas/openapi.yaml
    openapi: 3.1.0
    info:
      title: My API
      version: 1.0.0
    paths:
      /todos:
        get:
          operationId: Todos.list
      /todos/{id}:
        get:
          operationId: Todos.get

Run with:

    pagi-server --app app.pl

Visit C</docs> for Swagger UI, C</openapi.json> for the schema.

=head1 DESCRIPTION

PAGI::OpenAPI is a schema-first framework layer for L<PAGI>. You define your
API in OpenAPI 3.x format, and PAGI::OpenAPI automatically:

=over 4

=item * Routes requests to handler methods based on C<operationId>

=item * Validates requests against the schema

=item * Serves the schema at C</openapi.json> and C</openapi.yaml>

=item * Provides Swagger UI at C</docs>

=back

=head1 SERVICE PATTERN

PAGI::OpenAPI uses a service pattern for dependency injection where
B<return type determines scope>:

=over 4

=item * B<Return object/value> -> App-scoped (singleton, persists forever)

=item * B<Return coderef> -> Request-scoped (new instance per request)

=back

    sub setup_services {
        my ($self) = @_;

        # App-scoped: returns object directly
        $self->service(db => sub {
            my ($app) = @_;
            return DBI->connect($dsn);  # Cached forever
        });

        # Request-scoped: returns coderef
        $self->service(user => sub {
            my ($app) = @_;
            return sub {
                my ($c) = @_;
                return User->from_token($c->bearer_token);
            };
        });
    }

Services are accessed directly on the context object: C<< $c->db >>,
C<< $c->user >>, etc.

=head1 CONFIGURATION METHODS

Override these in your subclass:

=head2 openapi_schema

    sub openapi_schema { 'schemas/openapi.yaml' }

Path to your OpenAPI schema file (YAML or JSON). Relative paths are resolved
against the application's L</home> directory. The schema can use C<$ref>
to reference other files.

=head2 handler_namespace

    sub handler_namespace { 'MyAPI::Handlers' }

Namespace prefix for handler classes. Defaults to C<YourApp::Handlers>.

=head2 enable_docs

    sub enable_docs { 1 }

Enable Swagger UI at C</docs>. Default: true.

=head2 enable_validation

    sub enable_validation { 1 }

Enable request validation. Default: true.

=head2 operation_separator

    sub operation_separator { '.' }

Separator between handler name and method in operationId. Default: C<.>

=head2 setup_services

    sub setup_services {
        my ($self) = @_;
        $self->service(name => sub { ... });
    }

Register services for dependency injection. See L</SERVICE PATTERN> above.

=head2 setup_routes

    sub setup_routes {
        my ($self, $r) = @_;
        $r->get('/health' => async sub {
            my ($req, $res) = @_;
            await $res->json({ status => 'ok' });
        });
    }

Define additional routes not in the OpenAPI schema.

=head1 HOME DIRECTORY

PAGI::OpenAPI provides automatic home directory detection, similar to
L<Mojo::Home>. This ensures that relative paths (like schema files) work
correctly regardless of where the server is started from.

=head2 home

    my $home = $app->home;           # Path::Tiny object
    say $home;                       # /path/to/your/app

Returns the application's home directory as a L<Path::Tiny> object.

Detection order:

=over 4

=item 1. C<PAGI_HOME> environment variable (if set)

=item 2. Auto-detect from app class location (strips C<lib/> or C<blib/>)

=item 3. Fallback to current working directory

=back

Example: If your app class is at C</app/lib/MyAPI.pm>, home will be C</app>.

=head2 home_path

    my $schema = $app->home_path('schemas', 'openapi.yaml');
    my $config = $app->home_path('config', 'settings.json');

Convenience method that returns a path relative to home as a L<Path::Tiny>
object. Equivalent to C<< $app->home->child(@parts) >>.

=head2 Environment Variable Override

Set C<PAGI_HOME> to override auto-detection:

    PAGI_HOME=/app pagi-server --app lib/MyAPI.pm

This is useful for deployment when the working directory differs from the
app's home directory.

=head1 RUNNING AS A SCRIPT

=head2 run_if_script

    # At the end of your app module:
    __PACKAGE__->run_if_script;

Makes your app module directly runnable with pagi-server, similar to
L<Web::Simple>. Returns the app (with middleware applied) as the last
expression of the module.

    pagi-server -Ilib ./lib/MyAPI.pm

=head2 middleware

    sub middleware {
        return (
            'PAGI::Middleware::AccessLog',
            ['PAGI::Middleware::CORS', origins => ['*']],
            ['PAGI::Middleware::GZIP'],
        );
    }

Override to add middleware to your app. Middleware is specified as:

=over 4

=item * B<String>: Class name (loaded and instantiated with no args)

=item * B<Arrayref>: C<[ClassName, @args]> for middleware with options

=item * B<Coderef>: C<sub { my $app = shift; ... }> for inline wrapping

=back

Middleware is applied in order: first in list wraps outermost.

=head2 Example

    package MyAPI;
    use parent 'PAGI::OpenAPI';

    sub openapi_schema { 'schema.yaml' }

    sub middleware {
        return (
            'PAGI::Middleware::AccessLog',
            ['PAGI::Middleware::CORS', origins => ['https://example.com']],
            ['PAGI::Middleware::RateLimit', requests => 100, window => 60],
        );
    }

    # ... services, handlers, etc.

    __PACKAGE__->run_if_script;

=head1 SERVICE METHODS

=head2 service

    # Register a service (2 args)
    $self->service(name => sub {
        my ($app) = @_;
        return $object;  # or return sub { ... };
    });

    # Get a service (1 arg) - for use inside service factories
    my $db = $app->service('db');

When called with 2 arguments, registers a service. When called with 1
argument, returns an app-scoped service instance (for use within service
factories to access other services).

=head2 add_shutdown_callback

    $app->add_shutdown_callback(sub {
        $db->disconnect;
    });

Register a callback to run during server shutdown. Useful for cleaning up
app-scoped resources like database connections.

=head1 LIFESPAN HOOKS

=head2 on_startup

    async sub on_startup {
        my ($self, $scope) = @_;
        print "Server started!\n";
    }

Called when the server starts. Use for any startup logging or initialization
that can't be done in C<setup_services()>.

=head2 on_shutdown

    async sub on_shutdown {
        my ($self, $scope) = @_;
        print "Server stopping...\n";
    }

Called when the server shuts down, after service shutdown callbacks have run.

=head1 OPERATION ID MAPPING

The C<operationId> in your OpenAPI schema maps to handler classes and methods:

    operationId: Todos.list    -> MyAPI::Handlers::Todos->list($c)
    operationId: Todos.create  -> MyAPI::Handlers::Todos->create($c)
    operationId: Users.get     -> MyAPI::Handlers::Users->get($c)

If no separator is found, the operation is routed to a C<Default> handler:

    operationId: listTodos     -> MyAPI::Handlers::Default->list_todos($c)

=head1 BUILT-IN ENDPOINTS

=over 4

=item * C<GET /openapi.json> - Resolved schema as JSON

=item * C<GET /openapi.yaml> - Resolved schema as YAML

=item * C<GET /docs> - Swagger UI (if enabled)

=back

=head1 MULTI-FILE SCHEMAS

Use OpenAPI's C<$ref> to split your schema across files:

    # openapi.yaml
    paths:
      /todos:
        $ref: 'paths/todos.yaml#/paths/~1todos'

    components:
      schemas:
        Todo:
          $ref: 'components/todo.yaml#/Todo'

=head1 SEE ALSO

L<PAGI::OpenAPI::Context>, L<PAGI::OpenAPI::Handler>, L<OpenAPI::Modern>

=cut
