use strict;
use warnings;
use Test2::V0;
use PAGI::OpenAPI::Bridge;

# Test scope_to_psgi_env conversion
subtest 'scope_to_psgi_env basic' => sub {
    my $scope = {
        type         => 'http',
        method       => 'GET',
        path         => '/users/42',
        query_string => 'page=1&limit=10',
        scheme       => 'https',
        http_version => '1.1',
        client       => ['192.168.1.1', 54321],
        headers      => [
            ['host', 'example.com'],
            ['accept', 'application/json'],
            ['content-type', 'application/json'],
            ['content-length', '15'],
        ],
    };

    my $env = PAGI::OpenAPI::Bridge->scope_to_psgi_env($scope, '{"test":"data"}');

    is $env->{REQUEST_METHOD}, 'GET', 'method';
    is $env->{PATH_INFO}, '/users/42', 'path';
    is $env->{QUERY_STRING}, 'page=1&limit=10', 'query string';
    is $env->{SERVER_PROTOCOL}, 'HTTP/1.1', 'protocol';
    is $env->{REMOTE_ADDR}, '192.168.1.1', 'client addr';
    is $env->{REMOTE_PORT}, 54321, 'client port';
    is $env->{HTTP_HOST}, 'example.com', 'host header';
    is $env->{HTTP_ACCEPT}, 'application/json', 'accept header';
    is $env->{CONTENT_TYPE}, 'application/json', 'content type';
    is $env->{CONTENT_LENGTH}, '15', 'content length';
    is $env->{'psgi.url_scheme'}, 'https', 'scheme';

    # Check psgi.input
    ok $env->{'psgi.input'}, 'has psgi.input';
    my $body = do { local $/; readline($env->{'psgi.input'}) };
    is $body, '{"test":"data"}', 'body content';
};

subtest 'scope_to_psgi_env minimal' => sub {
    my $scope = {
        type   => 'http',
        method => 'POST',
        path   => '/',
    };

    my $env = PAGI::OpenAPI::Bridge->scope_to_psgi_env($scope);

    is $env->{REQUEST_METHOD}, 'POST', 'method';
    is $env->{PATH_INFO}, '/', 'path defaults';
    is $env->{QUERY_STRING}, '', 'query string defaults';
    is $env->{REMOTE_ADDR}, '127.0.0.1', 'default remote addr';
    is $env->{'psgi.url_scheme'}, 'http', 'default scheme';
};

subtest 'scope_to_psgi_env multi-value headers' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        path    => '/',
        headers => [
            ['accept', 'text/html'],
            ['accept', 'application/json'],
            ['x-custom', 'value1'],
        ],
    };

    my $env = PAGI::OpenAPI::Bridge->scope_to_psgi_env($scope);

    # Multi-value headers should be combined with comma
    is $env->{HTTP_ACCEPT}, 'text/html, application/json', 'multi-value accept';
    is $env->{HTTP_X_CUSTOM}, 'value1', 'custom header';
};

# Test that Plack::Request can be created from the env
subtest 'creates valid Plack::Request' => sub {
    eval { require Plack::Request } or skip_all 'Plack::Request not installed';

    my $scope = {
        type         => 'http',
        method       => 'GET',
        path         => '/api/users',
        query_string => 'id=42',
        headers      => [
            ['host', 'api.example.com'],
        ],
    };

    my $env = PAGI::OpenAPI::Bridge->scope_to_psgi_env($scope);
    my $req = Plack::Request->new($env);

    is $req->method, 'GET', 'Plack::Request method';
    is $req->path_info, '/api/users', 'Plack::Request path';
    is $req->param('id'), '42', 'Plack::Request param';
};

done_testing;
