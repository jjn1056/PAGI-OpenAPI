package PAGI::OpenAPI::Bridge;

use strict;
use warnings;
use Carp qw(croak);

# Convert PAGI scope to PSGI environment hash
# This allows us to use Plack::Request with OpenAPI::Modern
sub scope_to_psgi_env {
    my ($class, $scope, $body) = @_;

    my %env = (
        REQUEST_METHOD  => $scope->{method} // 'GET',
        SCRIPT_NAME     => '',
        PATH_INFO       => $scope->{path} // '/',
        QUERY_STRING    => $scope->{query_string} // '',
        SERVER_NAME     => 'localhost',
        SERVER_PORT     => 80,
        SERVER_PROTOCOL => 'HTTP/' . ($scope->{http_version} // '1.1'),
        'psgi.version'      => [1, 1],
        'psgi.url_scheme'   => $scope->{scheme} // 'http',
        'psgi.multithread'  => 0,
        'psgi.multiprocess' => 0,
        'psgi.run_once'     => 0,
        'psgi.nonblocking'  => 1,
        'psgi.streaming'    => 1,
    );

    # Client info
    if (my $client = $scope->{client}) {
        $env{REMOTE_ADDR} = $client->[0] if defined $client->[0];
        $env{REMOTE_PORT} = $client->[1] if defined $client->[1];
    } else {
        $env{REMOTE_ADDR} = '127.0.0.1';
    }

    # Convert headers
    for my $pair (@{$scope->{headers} // []}) {
        my ($name, $value) = @$pair;
        $name = uc($name);
        $name =~ s/-/_/g;

        if ($name eq 'CONTENT_TYPE') {
            $env{CONTENT_TYPE} = $value;
        }
        elsif ($name eq 'CONTENT_LENGTH') {
            $env{CONTENT_LENGTH} = $value;
        }
        else {
            my $key = "HTTP_$name";
            # Combine multiple values with comma (RFC 7230)
            if (exists $env{$key}) {
                $env{$key} .= ", $value";
            } else {
                $env{$key} = $value;
            }
        }
    }

    # Body as psgi.input
    if (defined $body && length $body) {
        open my $fh, '<', \$body or croak "Cannot create in-memory filehandle: $!";
        binmode $fh;
        $env{'psgi.input'} = $fh;
        $env{CONTENT_LENGTH} //= length $body;
    } else {
        # Empty input stream
        open my $fh, '<', \'' or croak "Cannot create empty filehandle: $!";
        $env{'psgi.input'} = $fh;
    }

    # Error stream
    $env{'psgi.errors'} = \*STDERR;

    return \%env;
}

# Validate a PAGI request using OpenAPI::Modern
sub validate_request {
    my ($class, $openapi, $scope, %opts) = @_;

    require Plack::Request;

    my $body = $scope->{'pagi.request.body'} // '';
    my $env = $class->scope_to_psgi_env($scope, $body);
    my $plack_req = Plack::Request->new($env);

    return $openapi->validate_request($plack_req, {
        path_template => $opts{path_template},
        path_captures => $opts{path_captures} // $scope->{path_params},
        method        => $opts{method} // lc($scope->{method}),
    });
}

# Convert response data to Plack::Response for validation
sub validate_response {
    my ($class, $openapi, $status, $headers, $body, %opts) = @_;

    require Plack::Response;

    my $plack_res = Plack::Response->new($status);

    # Add headers
    if (ref $headers eq 'ARRAY') {
        for (my $i = 0; $i < @$headers; $i += 2) {
            $plack_res->header($headers->[$i] => $headers->[$i + 1]);
        }
    } elsif (ref $headers eq 'HASH') {
        for my $name (keys %$headers) {
            $plack_res->header($name => $headers->{$name});
        }
    }

    # Set body
    $plack_res->body($body) if defined $body;

    return $openapi->validate_response($plack_res->finalize, {
        path_template => $opts{path_template},
        path_captures => $opts{path_captures},
        method        => $opts{method},
    });
}

1;

__END__

=head1 NAME

PAGI::OpenAPI::Bridge - Convert between PAGI and Plack for OpenAPI validation

=head1 SYNOPSIS

    use PAGI::OpenAPI::Bridge;
    use OpenAPI::Modern;
    use Plack::Request;

    my $openapi = OpenAPI::Modern->new(
        openapi_uri    => 'openapi.yaml',
        openapi_schema => $schema,
    );

    # Convert PAGI scope to PSGI env
    my $env = PAGI::OpenAPI::Bridge->scope_to_psgi_env($scope, $body);
    my $plack_req = Plack::Request->new($env);

    # Or validate directly
    my $result = PAGI::OpenAPI::Bridge->validate_request(
        $openapi, $scope,
        path_template => '/todos/{id}',
        method        => 'get',
    );

    if (!$result) {
        # Validation failed
        my $errors = $result->TO_JSON;
    }

=head1 DESCRIPTION

PAGI::OpenAPI::Bridge provides utilities for converting between PAGI's
scope/request format and Plack::Request/Response objects. This enables
integration with L<OpenAPI::Modern> for request and response validation.

OpenAPI::Modern accepts various request types including Plack::Request,
which maps closely to PAGI's scope structure.

=head1 CLASS METHODS

=head2 scope_to_psgi_env

    my $env = PAGI::OpenAPI::Bridge->scope_to_psgi_env($scope, $body);

Converts a PAGI scope hashref to a PSGI environment hash suitable for
creating a L<Plack::Request>.

=over 4

=item $scope

The PAGI scope hashref containing C<method>, C<path>, C<query_string>,
C<headers>, C<scheme>, C<http_version>, and C<client>.

=item $body

Optional request body as a string. Will be made available as C<psgi.input>.

=back

Returns a hashref suitable for C<< Plack::Request->new($env) >>.

=head2 validate_request

    my $result = PAGI::OpenAPI::Bridge->validate_request(
        $openapi, $scope,
        path_template => '/users/{id}',
        path_captures => { id => 42 },
        method        => 'get',
    );

Validates a PAGI request against an OpenAPI schema.

=over 4

=item $openapi

An L<OpenAPI::Modern> instance.

=item $scope

The PAGI scope hashref. The body should be pre-buffered in
C<< $scope->{'pagi.request.body'} >>.

=item path_template

The OpenAPI path template (e.g., C</users/{id}>).

=item path_captures

Hashref of path parameter values. Defaults to C<< $scope->{path_params} >>.

=item method

HTTP method (lowercase). Defaults to C<< lc($scope->{method}) >>.

=back

Returns a L<JSON::Schema::Modern::Result> object. Check with C<< if ($result) >>
for success, or access C<< $result->TO_JSON >> for error details.

=head2 validate_response

    my $result = PAGI::OpenAPI::Bridge->validate_response(
        $openapi, $status, $headers, $body,
        path_template => '/users/{id}',
        method        => 'get',
    );

Validates a response against an OpenAPI schema.

=over 4

=item $openapi

An L<OpenAPI::Modern> instance.

=item $status

HTTP status code (e.g., 200).

=item $headers

Response headers as arrayref or hashref.

=item $body

Response body as string.

=item path_template, path_captures, method

Same as C<validate_request>.

=back

Returns a L<JSON::Schema::Modern::Result> object.

=head1 SEE ALSO

L<PAGI::OpenAPI>, L<OpenAPI::Modern>, L<Plack::Request>, L<Plack::Response>

=cut
