# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PAGI::OpenAPI is a schema-first OpenAPI framework layer for PAGI (Perl Asynchronous Gateway Interface). It provides automatic routing based on OpenAPI 3.x schemas, request/response validation, and a rich per-request context object.

**Requirements**: Perl 5.18+, PAGI, OpenAPI::Modern

## Common Commands

```bash
# Install dependencies
cpanm --installdeps .
cpanm --installdeps . --with-develop  # include dev deps

# Run tests
prove -l t/                    # all tests
prove -l t/openapi-basic.t     # single test

# Build distribution
dzil build
dzil test
```

## Architecture

### Core Modules

- **PAGI::OpenAPI** (`lib/PAGI/OpenAPI.pm`) - Main base class for apps. Handles schema loading, route wiring, lifespan integration, and built-in endpoints.

- **PAGI::OpenAPI::Context** (`lib/PAGI/OpenAPI/Context.pm`) - Per-request context object passed to handlers. Provides request/response methods and dynamic service access.

- **PAGI::OpenAPI::Handler** (`lib/PAGI/OpenAPI/Handler.pm`) - Base class for handler classes.

- **PAGI::OpenAPI::Bridge** (`lib/PAGI/OpenAPI/Bridge.pm`) - Converts PAGI scope to PSGI env for OpenAPI::Modern validation.

### Usage Pattern

```perl
# Main app (inherits from PAGI::OpenAPI)
package MyAPI;
use parent 'PAGI::OpenAPI';

sub openapi_schema { 'schema.yaml' }

# Services: return type determines scope
#   - Return object = app-scoped (singleton)
#   - Return coderef = request-scoped (per-request)
sub setup_services {
    my ($self) = @_;

    # App-scoped: returns object directly
    $self->service(db => sub {
        my ($app) = @_;
        my $db = DBI->connect($ENV{DATABASE_URL});
        $app->add_shutdown_callback(sub { $db->disconnect });
        return $db;
    });

    # Request-scoped: returns coderef
    $self->service(current_user => sub {
        my ($app) = @_;
        return sub {
            my ($c) = @_;
            my $token = $c->bearer_token or return;
            return decode_jwt($token);
        };
    });
}

# Handler class
package MyAPI::Handlers::Todos;
use parent 'PAGI::OpenAPI::Handler';

async sub list {
    my ($self, $c) = @_;
    my $todos = $c->db->selectall_arrayref('SELECT * FROM todos');
    await $c->json({ todos => $todos });
}
```

### operationId Mapping

```yaml
# schema.yaml
paths:
  /todos:
    get:
      operationId: Todos.list  # -> MyAPI::Handlers::Todos->list($c)
```

### Home Directory

Schema paths and other resources are resolved relative to the app's home directory:

```perl
# Auto-detected from class location (strips lib/ or blib/)
my $home = $app->home;           # Path::Tiny object

# Build paths relative to home
my $config = $app->home_path('config', 'settings.yaml');

# Override with environment variable
# PAGI_HOME=/app pagi-server --app lib/MyAPI.pm
```

### Running as Script

Make your app module directly runnable (like Web::Simple):

```perl
# At the end of your app module:
__PACKAGE__->run_if_script;

# Optional: add middleware
sub middleware {
    return (
        'PAGI::Middleware::AccessLog',
        ['PAGI::Middleware::CORS', origins => ['*']],
    );
}
```

Then run without needing an app.pl:

```bash
pagi-server -Ilib ./lib/MyAPI.pm --port 5000
```

## Testing

```bash
prove -l t/                    # Full suite
prove -l t/openapi-basic.t     # Integration tests
prove -l t/openapi-context.t   # Context unit tests
prove -l t/openapi-bridge.t    # Bridge unit tests
prove -l t/openapi-home.t      # Home directory tests
```

Test framework: Test2::V0
