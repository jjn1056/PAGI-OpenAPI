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

- **PAGI::OpenAPI::Context** (`lib/PAGI/OpenAPI/Context.pm`) - Per-request context object passed to handlers. Provides request/response methods and dynamic helper access.

- **PAGI::OpenAPI::Handler** (`lib/PAGI/OpenAPI/Handler.pm`) - Base class for handler classes.

- **PAGI::OpenAPI::Bridge** (`lib/PAGI/OpenAPI/Bridge.pm`) - Converts PAGI scope to PSGI env for OpenAPI::Modern validation.

### Usage Pattern

```perl
# Main app (inherits from PAGI::OpenAPI)
package MyAPI;
use parent 'PAGI::OpenAPI';

sub openapi_schema { 'schema.yaml' }

sub build_helpers {
    my ($self, $state) = @_;
    return { db => $state->{db} };
}

async sub on_startup {
    my ($self, $scope) = @_;
    $self->state->{db} = await connect_db();
}

# Handler class
package MyAPI::Handlers::Todos;
use parent 'PAGI::OpenAPI::Handler';

async sub list {
    my ($self, $c) = @_;
    my $todos = await $c->db->query('SELECT * FROM todos');
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

## Testing

```bash
prove -l t/                    # Full suite
prove -l t/openapi-basic.t     # Integration tests
prove -l t/openapi-context.t   # Context unit tests
prove -l t/openapi-bridge.t    # Bridge unit tests
```

Test framework: Test2::V0
