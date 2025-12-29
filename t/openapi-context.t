use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;
use PAGI::OpenAPI::Context;

# Mock app for testing
package MockApp {
    sub new {
        my $class = shift;
        bless {
            _state    => {},
            _services => {},
        }, $class;
    }
    sub state { shift->{_state} }

    # Mock _get_service that returns cached instances
    sub _get_service {
        my ($self, $name) = @_;
        my $svc = $self->{_services}{$name} or return;

        # Resolve if not yet resolved
        if (!defined $svc->{is_request_scoped}) {
            my $result = $svc->{factory}->($self);
            if (ref($result) eq 'CODE') {
                $svc->{is_request_scoped} = 1;
                $svc->{request_factory} = $result;
            } else {
                $svc->{is_request_scoped} = 0;
                $svc->{instance} = $result;
            }
        }

        return $svc->{instance};
    }
}

# Create a test scope
sub test_scope {
    return {
        type         => 'http',
        method       => 'GET',
        path         => '/users/42',
        query_string => 'page=1&limit=10',
        scheme       => 'https',
        http_version => '1.1',
        headers      => [
            ['host', 'example.com'],
            ['accept', 'application/json'],
            ['authorization', 'Bearer abc123'],
            ['cookie', 'session=xyz'],
        ],
        path_params  => { id => '42' },
        'pagi.stash' => {},
    };
}

subtest 'basic properties' => sub {
    my $app = MockApp->new;
    my $c = PAGI::OpenAPI::Context->new(
        app     => $app,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    is $c->method, 'GET', 'method';
    is $c->path, '/users/42', 'path';
    is $c->query_string, 'page=1&limit=10', 'query_string';
    is $c->scheme, 'https', 'scheme';
    is $c->host, 'example.com', 'host';
    ok $c->is_get, 'is_get';
    ok !$c->is_post, 'not is_post';
};

subtest 'query params' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    is $c->query('page'), '1', 'query param';
    is $c->query('limit'), '10', 'query param 2';
    is $c->query('missing'), undef, 'missing param';
};

subtest 'path params' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    is $c->path_param('id'), '42', 'path param';
    is $c->path_param('missing'), undef, 'missing path param';

    my $params = $c->path_params;
    is $params->{id}, '42', 'path_params hash';
};

subtest 'headers' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    is $c->header('accept'), 'application/json', 'header';
    is $c->header('host'), 'example.com', 'host header';
};

subtest 'auth methods' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    is $c->bearer_token, 'abc123', 'bearer token';
};

subtest 'cookies' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    is $c->cookie('session'), 'xyz', 'cookie';
};

subtest 'stash' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    $c->stash->{user} = { id => 1, name => 'Test' };
    is $c->stash->{user}{id}, 1, 'stash set/get';
};


subtest 'response chainable methods' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    # Chainable methods return $c
    my $result = $c->status(201);
    is $result, $c, 'status returns $c';

    $result = $c->set_header('X-Custom', 'value');
    is $result, $c, 'set_header returns $c';

    # Can chain
    $result = $c->status(200)->set_header('X-Test', 'test');
    is $result, $c, 'chaining works';
};

subtest 'app-scoped services via AUTOLOAD' => sub {
    my $app = MockApp->new;

    # Register an app-scoped service (returns object, not coderef)
    $app->{_services}{db} = {
        factory => sub {
            my ($app) = @_;
            return { name => 'mock_db', connected => 1 };  # Returns object = app-scoped
        },
        instance => undef,
        is_request_scoped => undef,
        request_factory => undef,
    };

    my $c = PAGI::OpenAPI::Context->new(
        app      => $app,
        scope    => test_scope(),
        receive  => sub { },
        send     => sub { },
        services => $app->{_services},
    );

    my $db = $c->db;
    is $db->{name}, 'mock_db', 'app-scoped service accessible';
    is $db->{connected}, 1, 'service has expected properties';

    # Second access should return same instance
    my $db2 = $c->db;
    is $db2, $db, 'app-scoped service returns same instance';
};

subtest 'request-scoped services via AUTOLOAD' => sub {
    my $app = MockApp->new;

    # Register a request-scoped service (returns coderef)
    my $call_count = 0;
    $app->{_services}{user} = {
        factory => sub {
            my ($app) = @_;
            return sub {  # Returns coderef = request-scoped
                my ($c) = @_;
                $call_count++;
                return { name => 'current_user', request_id => $call_count };
            };
        },
        instance => undef,
        is_request_scoped => undef,
        request_factory => undef,
    };

    my $c = PAGI::OpenAPI::Context->new(
        app      => $app,
        scope    => test_scope(),
        receive  => sub { },
        send     => sub { },
        services => $app->{_services},
    );

    my $user = $c->user;
    is $user->{name}, 'current_user', 'request-scoped service accessible';
    is $user->{request_id}, 1, 'factory was called';

    # Second access should return cached instance (no args)
    my $user2 = $c->user;
    is $user2, $user, 'request-scoped service is cached within request';
    is $call_count, 1, 'factory only called once';
};

subtest 'on_request_end callbacks' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
    );

    my @calls;
    $c->on_request_end(sub { push @calls, 'first' });
    $c->on_request_end(sub { push @calls, 'second' });

    is scalar(@calls), 0, 'callbacks not called yet';

    $c->_run_request_end_callbacks;

    is scalar(@calls), 2, 'both callbacks called';
    is $calls[0], 'first', 'first callback ran';
    is $calls[1], 'second', 'second callback ran';
};

subtest 'can() works with services' => sub {
    my $app = MockApp->new;
    $app->{_services}{db} = {
        factory => sub { return { name => 'db' } },
        instance => undef,
        is_request_scoped => undef,
        request_factory => undef,
    };

    my $c = PAGI::OpenAPI::Context->new(
        app      => $app,
        scope    => test_scope(),
        receive  => sub { },
        send     => sub { },
        services => $app->{_services},
    );

    ok $c->can('req'), 'can() for real methods';
    ok $c->can('db'), 'can() for services';
    ok !$c->can('nonexistent_service'), 'can() returns false for unknown services';
};

done_testing;
