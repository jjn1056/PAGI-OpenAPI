package PAGI::OpenAPI;

use strict;
use warnings;
use parent 'PAGI::Endpoint::Router';
use Future::AsyncAwait;
use Module::Load qw(load);
use Carp qw(croak);
use Scalar::Util qw(blessed);
use JSON::MaybeXS qw(encode_json);

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

# Build helpers available via $c->helper_name
sub build_helpers {
    my ($self, $state) = @_;
    return {};
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
# Route building
# ============================================================

sub routes {
    my ($self, $r) = @_;

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

    croak "Schema file not found: $file" unless -f $file;

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

            # Register route
            $r->$method($pagi_path => $handler);
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

        # Build helpers if not yet built
        $app->_ensure_helpers_built();

        # Get scope from request for context and validation
        my $scope = $req->{scope};

        # Create context with request/response objects
        require PAGI::OpenAPI::Context;
        my $c = PAGI::OpenAPI::Context->new(
            app           => $app,
            scope         => $scope,
            receive       => $req->{receive},
            send          => $res->{send},
            helpers       => $app->state->{_helpers},
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
                return await $c->status(400)->json({
                    error   => 'Request validation failed',
                    details => $result->TO_JSON,
                });
            }
        }

        # Get handler instance
        my $handler = $app->_get_handler($handler_name);

        # Call method
        my $code = $handler->can($method_name)
            or croak "No method '$method_name' in " . ref($handler)
                   . " (for operationId: $handler_name.$method_name)";

        await $handler->$code($c);
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

sub _ensure_helpers_built {
    my $self = shift;

    return if $self->state->{_helpers_built};

    $self->state->{_helpers} = $self->build_helpers($self->state);
    $self->state->{_helpers_built} = 1;
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
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIBundle.SwaggerUIStandalonePreset
                ],
                layout: "StandaloneLayout"
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

    # Let subclass define routes
    $instance->_build_routes($internal_router);

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
            # Build helpers after startup populates state
            $instance->_ensure_helpers_built();
        },
        shutdown => async sub {
            my ($lifespan_state) = @_;
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

    sub build_helpers {
        my ($self, $state) = @_;
        return {
            pg     => $state->{pg},
            config => $state->{config},
        };
    }

    async sub on_startup {
        my ($self, $scope) = @_;

        require IO::Async::Pg;
        my $pg = IO::Async::Pg->new(dsn => $ENV{DATABASE_URL});
        IO::Async::Loop->new->add($pg);

        $self->state->{pg} = $pg;
        $self->state->{config} = { jwt_secret => $ENV{JWT_SECRET} };
    }

    1;

Then create handler classes:

    package MyAPI::Handlers::Todos;
    use parent 'PAGI::OpenAPI::Handler';
    use Future::AsyncAwait;

    async sub list {
        my ($self, $c) = @_;
        my $todos = await $c->pg->query_all_f('SELECT * FROM todos');
        await $c->json({ todos => $todos });
    }

    async sub get {
        my ($self, $c) = @_;
        my $id = $c->path_param('id');
        my $todo = await $c->pg->query_one_f(
            'SELECT * FROM todos WHERE id = $1', $id
        );
        return await $c->not_found unless $todo;
        await $c->json($todo);
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

=head1 CONFIGURATION METHODS

Override these in your subclass:

=head2 openapi_schema

    sub openapi_schema { 'schemas/openapi.yaml' }

Path to your OpenAPI schema file (YAML or JSON). The schema can use C<$ref>
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

=head2 build_helpers

    sub build_helpers {
        my ($self, $state) = @_;
        return {
            pg     => $state->{pg},
            redis  => $state->{redis},
            config => $state->{config},
        };
    }

Define helpers accessible via C<< $c->helper_name >> in handlers.

=head2 setup_routes

    sub setup_routes {
        my ($self, $r) = @_;
        $r->get('/health' => async sub {
            my ($req, $res) = @_;
            await $res->json({ status => 'ok' });
        });
    }

Define additional routes not in the OpenAPI schema.

=head1 LIFESPAN HOOKS

=head2 on_startup

    async sub on_startup {
        my ($self, $scope) = @_;
        # Initialize database, load config, etc.
        $self->state->{db} = await connect_db();
    }

Called when the server starts. Use to initialize resources.

=head2 on_shutdown

    async sub on_shutdown {
        my ($self, $scope) = @_;
        await $self->state->{db}->disconnect;
    }

Called when the server shuts down. Use to clean up resources.

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
