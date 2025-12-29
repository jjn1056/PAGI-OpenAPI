package BookstoreAPI::Handlers::Auth;

use strict;
use warnings;
use parent 'PAGI::OpenAPI::Handler';
use Future::AsyncAwait;

async sub login {
    my ($self, $c) = @_;

    my $data = await $c->request_json;
    my $username = $data->{username};

    # For demo, accept any credentials
    my $token = $c->auth->create_token($username);

    await $c->json({
        token => $token,
        user  => $username,
    });
}

1;

__END__

=head1 NAME

BookstoreAPI::Handlers::Auth - Authentication handler

=head1 METHODS

=head2 login

    POST /auth/token

Accepts any username/password and returns a token.

=cut
