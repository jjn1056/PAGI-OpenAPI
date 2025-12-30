package PAGI::OpenAPI::Context;

use strict;
use warnings;
use Future::AsyncAwait;
use Carp qw(croak);
use Scalar::Util qw(blessed);

sub new {
    my ($class, %args) = @_;

    # Validate required parameters
    for my $required (qw(app scope receive send)) {
        croak "Missing required parameter: $required"
            unless defined $args{$required};
    }

    my $self = bless {
        app            => $args{app},
        scope          => $args{scope},
        receive        => $args{receive},
        send           => $args{send},
        services       => $args{services} // {},
        path_template  => $args{path_template},
        http_method    => $args{http_method},
        _req           => $args{_req},    # Can be pre-built
        _res           => $args{_res},    # Can be pre-built
        _response_status => 200,
    }, $class;

    return $self;
}

# Check if we're in development mode (defaults to production for security)
sub _is_dev_mode {
    return ($ENV{PAGI_ENV} // 'production') eq 'development';
}

# Lazy request object
sub req {
    my $self = shift;
    return $self->{_req} if $self->{_req};

    require PAGI::Request;
    $self->{_req} = PAGI::Request->new($self->{scope}, $self->{receive});
    return $self->{_req};
}

# Lazy response object
sub res {
    my $self = shift;
    return $self->{_res} if $self->{_res};

    require PAGI::Response;
    $self->{_res} = PAGI::Response->new($self->{scope}, $self->{send});
    return $self->{_res};
}

# App reference
sub app { shift->{app} }

# Raw scope access
sub scope { shift->{scope} }

# Request-scoped stash (shared with middleware)
sub stash {
    my $self = shift;
    $self->{scope}{'pagi.stash'} //= {};
}

# App state (read-only, from lifespan)
sub state {
    my $self = shift;
    return $self->{app}->state;
}

# ============================================================
# Request convenience methods (delegate to req)
# ============================================================

sub method       { shift->req->method }
sub path         { shift->req->path }
sub raw_path     { shift->req->raw_path }
sub query_string { shift->req->query_string }
sub scheme       { shift->req->scheme }
sub host         { shift->req->host }
sub content_type { shift->req->content_type }

sub query        { shift->req->query(@_) }
sub query_params { shift->req->query_params(@_) }
sub path_param   { shift->req->path_param(@_) }
sub path_params  { shift->req->path_params(@_) }
sub header       { shift->req->header(@_) }
sub headers      { shift->req->headers(@_) }
sub cookie       { shift->req->cookie(@_) }
sub cookies      { shift->req->cookies(@_) }

sub bearer_token { shift->req->bearer_token }
sub basic_auth   { shift->req->basic_auth }

sub is_get     { shift->req->is_get }
sub is_post    { shift->req->is_post }
sub is_put     { shift->req->is_put }
sub is_patch   { shift->req->is_patch }
sub is_delete  { shift->req->is_delete }
sub is_json    { shift->req->is_json }
sub is_form    { shift->req->is_form }
sub accepts    { shift->req->accepts(@_) }

# Async request methods
async sub body { await shift->req->body(@_) }

# Note: We use request_* prefix for reading request body to avoid
# conflicts with response methods (json, text)
async sub request_text { await shift->req->text(@_) }
async sub request_json { await shift->req->json(@_) }
async sub form         { await shift->req->form(@_) }
async sub upload       { await shift->req->upload(@_) }
async sub uploads      { await shift->req->uploads(@_) }

# ============================================================
# Response chainable methods (return $self for chaining)
# ============================================================

sub status {
    my ($self, $code) = @_;
    $self->{_response_status} = $code;
    $self->res->status($code);
    return $self;
}

sub set_header {
    my ($self, $name, $value) = @_;
    $self->res->header($name => $value);
    return $self;
}

sub set_cookie {
    my ($self, $name, $value, %opts) = @_;
    $self->res->cookie($name => $value, %opts);
    return $self;
}

sub content_type_response {
    my ($self, $type) = @_;
    $self->res->content_type($type);
    return $self;
}

# ============================================================
# Response finishers (async, send response)
# ============================================================

async sub json {
    my ($self, $data) = @_;

    $self->{_response_started} = 1;

    # Response validation in dev mode
    if ($self->_is_dev_mode && $self->{app} && $self->{path_template}) {
        $self->_validate_response($data);
    }

    await $self->res->json($data);
}

sub _validate_response {
    my ($self, $data) = @_;

    my $openapi = $self->{app}->state->{_openapi};
    return unless $openapi;

    require PAGI::OpenAPI::Bridge;
    require JSON::MaybeXS;

    my $body = JSON::MaybeXS::encode_json($data);
    my $headers = ['Content-Type' => 'application/json'];

    my $result = PAGI::OpenAPI::Bridge->validate_response(
        $openapi,
        $self->{_response_status},
        $headers,
        $body,
        path_template => $self->{path_template},
        path_captures => $self->{scope}{path_params},
        method        => $self->{http_method},
    );

    if (!$result->valid) {
        warn "[PAGI::OpenAPI] Response validation failed for "
            . uc($self->{http_method}) . " $self->{path_template}: "
            . JSON::MaybeXS::encode_json($result->TO_JSON) . "\n";
    }
}

async sub text {
    my ($self, $text) = @_;
    $self->{_response_started} = 1;
    await $self->res->text($text);
}

async sub html {
    my ($self, $html) = @_;
    $self->{_response_started} = 1;
    await $self->res->html($html);
}

async sub send {
    my $self = shift;
    $self->{_response_started} = 1;
    # Use send_raw for empty body (e.g., 204 responses)
    await $self->res->send_raw('');
}

async sub redirect {
    my ($self, $url, $status) = @_;
    $self->{_response_started} = 1;
    await $self->res->redirect($url, $status);
}

async sub send_file {
    my ($self, $path, %opts) = @_;
    $self->{_response_started} = 1;
    await $self->res->send_file($path, %opts);
}

# ============================================================
# Error response shortcuts
# ============================================================

async sub not_found {
    my ($self, $message) = @_;
    $message //= 'Not found';
    await $self->status(404)->json({ error => $message });
}

async sub bad_request {
    my ($self, $message, $details) = @_;
    $message //= 'Bad request';
    my $body = { error => $message };
    $body->{details} = $details if defined $details;
    await $self->status(400)->json($body);
}

async sub unauthorized {
    my ($self, $message) = @_;
    $message //= 'Unauthorized';
    await $self->status(401)->json({ error => $message });
}

async sub forbidden {
    my ($self, $message) = @_;
    $message //= 'Forbidden';
    await $self->status(403)->json({ error => $message });
}

async sub conflict {
    my ($self, $message) = @_;
    $message //= 'Conflict';
    await $self->status(409)->json({ error => $message });
}

async sub unprocessable {
    my ($self, $message, $details) = @_;
    $message //= 'Unprocessable entity';
    my $body = { error => $message };
    $body->{details} = $details if defined $details;
    await $self->status(422)->json($body);
}

async sub server_error {
    my ($self, $message) = @_;
    $message //= 'Internal server error';
    await $self->status(500)->json({ error => $message });
}

# ============================================================
# URL Generation
# ============================================================

sub uri_for {
    my ($self, $name, $path_params, $query_params) = @_;
    my $router = $self->{app}{_router}
        or croak "No router available for uri_for";
    return $router->uri_for($name, $path_params, $query_params);
}

# ============================================================
# Request-end callbacks (for request-scoped service cleanup)
# ============================================================

sub on_request_end {
    my ($self, $cb) = @_;
    push @{$self->stash->{_request_end_callbacks}}, $cb;
}

sub _run_request_end_callbacks {
    my ($self) = @_;
    for my $cb (@{$self->stash->{_request_end_callbacks} // []}) {
        eval { $cb->() };
        warn "Request end cleanup error: $@" if $@;
    }
}

# ============================================================
# Dynamic service access via AUTOLOAD
# ============================================================

our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my @args = @_;
    my ($method) = $AUTOLOAD =~ /::(\w+)$/;

    return if $method eq 'DESTROY';

    # Security: reject service names starting with underscore
    # These could expose internal methods or private state
    if ($method =~ /^_/) {
        croak "Invalid service name: '$method' (names cannot start with underscore)";
    }

    # Check services
    if (exists $self->{services}{$method}) {
        return $self->_resolve_service($method, @args);
    }

    my @available = sort keys %{$self->{services} // {}};

    croak "Unknown service: $method. "
        . "Available: " . join(', ', @available);
}

sub _resolve_service {
    my ($self, $name, @args) = @_;

    my $svc = $self->{services}{$name};

    # Ensure factory has been called to determine scope
    if (!defined $svc->{is_request_scoped}) {
        $self->{app}->_get_service($name);
    }

    if ($svc->{is_request_scoped}) {
        # Request-scoped: check cache first (only if no args)
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

# Prevent AUTOLOAD from catching can()
sub can {
    my ($self, $method) = @_;

    # Check if it's a real method
    my $code = $self->SUPER::can($method);
    return $code if $code;

    # Check if it's a service
    if (ref $self && exists $self->{services}{$method}) {
        return sub { shift->_resolve_service($method) };
    }

    return undef;
}

1;

__END__

=head1 NAME

PAGI::OpenAPI::Context - Per-request context for OpenAPI handlers

=head1 SYNOPSIS

    async sub list_todos {
        my ($self, $c) = @_;

        # Request data
        my $limit = $c->query('limit') // 20;
        my $id = $c->path_param('id');
        my $data = await $c->request_json;

        # Helpers (defined in your app)
        my $todos = await $c->pg->query_all_f(
            'SELECT * FROM todos LIMIT $1', $limit
        );

        # Response
        await $c->json({ todos => $todos });
    }

    async sub get_todo {
        my ($self, $c) = @_;

        my $id = $c->path_param('id');
        my $todo = await $c->pg->query_one_f(
            'SELECT * FROM todos WHERE id = $1', $id
        );

        return await $c->not_found('Todo not found') unless $todo;
        await $c->json($todo);
    }

=head1 DESCRIPTION

PAGI::OpenAPI::Context is the per-request context object passed to handler
methods. It provides convenient access to the request, response, application
state, and custom helpers.

=head1 CONSTRUCTOR

=head2 new

    my $c = PAGI::OpenAPI::Context->new(
        app      => $app,
        scope    => $scope,
        receive  => $receive,
        send     => $send,
        services => $services,  # Service registry from app
    );

Creates a new context object. Normally called by PAGI::OpenAPI, not directly.

=head1 PROPERTIES

=head2 req

    my $req = $c->req;

Returns the L<PAGI::Request> object (lazily created).

=head2 res

    my $res = $c->res;

Returns the L<PAGI::Response> object (lazily created).

=head2 app

    my $app = $c->app;

Returns the parent PAGI::OpenAPI application instance.

=head2 scope

    my $scope = $c->scope;

Returns the raw PAGI scope hashref.

=head2 stash

    $c->stash->{user} = $user;
    my $user = $c->stash->{user};

Per-request storage hashref, shared with middleware.

=head2 state

    my $db = $c->state->{db};

Application state from lifespan (read-only).

=head1 REQUEST METHODS

These delegate to L<PAGI::Request>:

=head2 Synchronous

    $c->method          # GET, POST, etc.
    $c->path            # /users/42
    $c->query('page')   # Query parameter
    $c->query_params    # Hash::MultiValue
    $c->path_param('id') # Path parameter
    $c->header('Accept') # Header value
    $c->cookie('session') # Cookie value
    $c->bearer_token    # Bearer token from Authorization
    $c->is_get, $c->is_post, etc.
    $c->is_json, $c->is_form
    $c->accepts('json')

=head2 Asynchronous

    my $body = await $c->body;
    my $text = await $c->request_text;
    my $data = await $c->request_json;
    my $form = await $c->form;
    my $file = await $c->upload('avatar');

Note: Use C<request_json> and C<request_text> to read from the request body.
C<json> and C<text> are reserved for sending responses.

=head1 RESPONSE METHODS

=head2 Chainable (return $c)

    $c->status(201)
    $c->set_header('X-Custom' => 'value')
    $c->set_cookie('session' => $token, httponly => 1)

=head2 Finishers (async, send response)

    await $c->json($data);
    await $c->text($string);
    await $c->html($html);
    await $c->redirect($url);
    await $c->redirect($url, 301);
    await $c->send_file($path);
    await $c->send;  # Finalize response

=head1 ERROR SHORTCUTS

    await $c->not_found;
    await $c->not_found('Custom message');
    await $c->bad_request('Invalid input', { field => 'email' });
    await $c->unauthorized;
    await $c->forbidden;
    await $c->conflict;
    await $c->unprocessable('Validation failed', \@errors);
    await $c->server_error;

All error methods return JSON: C<< { error => "message", details => ... } >>

=head1 SERVICES

Services are defined in your PAGI::OpenAPI subclass via C<setup_services()>
and accessed as methods on the context:

    # In your app
    sub setup_services {
        my ($self) = @_;

        # App-scoped: returns object (singleton)
        $self->service(db => sub {
            my ($app) = @_;
            return DBI->connect($dsn);
        });

        # Request-scoped: returns coderef (per-request)
        $self->service(current_user => sub {
            my ($app) = @_;
            return sub {
                my ($c) = @_;
                return User->from_token($c->bearer_token);
            };
        });
    }

    # In handlers
    my $db = $c->db;           # App-scoped service
    my $user = $c->current_user; # Request-scoped service

=head2 on_request_end

    $c->on_request_end(sub {
        # Cleanup code runs after response is sent
        $transaction->rollback if $transaction->active;
    });

Register a callback to run when the request ends. Useful for cleaning up
request-scoped resources like database transactions.

=head1 SEE ALSO

L<PAGI::OpenAPI>, L<PAGI::OpenAPI::Handler>, L<PAGI::Request>, L<PAGI::Response>

=cut
