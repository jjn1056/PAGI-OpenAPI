use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;
use PAGI::OpenAPI::Context;

# Mock app for testing
package MockApp {
    sub new { bless { _state => {} }, shift }
    sub state { shift->{_state} }
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
        helpers => {},
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
        helpers => {},
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
        helpers => {},
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
        helpers => {},
    );

    is $c->header('accept'), 'application/json', 'header';
    is $c->header('host'), 'example.com', 'host header';
};

subtest 'auth helpers' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
        helpers => {},
    );

    is $c->bearer_token, 'abc123', 'bearer token';
};

subtest 'cookies' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
        helpers => {},
    );

    is $c->cookie('session'), 'xyz', 'cookie';
};

subtest 'stash' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
        helpers => {},
    );

    $c->stash->{user} = { id => 1, name => 'Test' };
    is $c->stash->{user}{id}, 1, 'stash set/get';
};

subtest 'helpers via AUTOLOAD' => sub {
    my $mock_pg = { name => 'mock_pg' };
    my $mock_redis = { name => 'mock_redis' };

    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
        helpers => {
            pg    => $mock_pg,
            redis => $mock_redis,
        },
    );

    is $c->pg, $mock_pg, 'pg helper';
    is $c->redis, $mock_redis, 'redis helper';
    is $c->pg->{name}, 'mock_pg', 'helper is the actual object';

    # Unknown helper should croak
    like dies { $c->unknown_helper }, qr/Unknown helper/, 'unknown helper dies';
};

subtest 'can() works with helpers' => sub {
    my $mock_db = { name => 'db' };

    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
        helpers => { db => $mock_db },
    );

    ok $c->can('req'), 'can() for real methods';
    ok $c->can('db'), 'can() for helpers';
    ok !$c->can('nonexistent'), 'can() returns false for unknown';
};

subtest 'response chainable methods' => sub {
    my $c = PAGI::OpenAPI::Context->new(
        app     => MockApp->new,
        scope   => test_scope(),
        receive => sub { },
        send    => sub { },
        helpers => {},
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

done_testing;
