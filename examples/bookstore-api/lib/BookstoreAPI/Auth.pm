package BookstoreAPI::Auth;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

sub new {
    my ($class, %args) = @_;
    return bless { secret => $args{secret} }, $class;
}

sub create_token {
    my ($self, $username) = @_;
    my $payload = "$username:" . time();
    my $sig = sha256_hex($payload . $self->{secret});
    return "$payload:$sig";
}

sub verify_token {
    my ($self, $token) = @_;
    return unless $token;

    my ($username, $timestamp, $sig) = split /:/, $token, 3;
    return unless $username && $timestamp && $sig;

    my $expected = sha256_hex("$username:$timestamp" . $self->{secret});
    return $username if $sig eq $expected;
    return;
}

1;

__END__

=head1 NAME

BookstoreAPI::Auth - Simple token-based authentication

=head1 SYNOPSIS

    my $auth = BookstoreAPI::Auth->new(secret => 'my-secret');

    my $token = $auth->create_token('username');
    my $username = $auth->verify_token($token);

=head1 DESCRIPTION

Simple HMAC-based token authentication for the bookstore demo.
In production, use a proper JWT library.

=cut
