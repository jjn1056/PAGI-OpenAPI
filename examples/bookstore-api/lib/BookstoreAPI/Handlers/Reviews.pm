package BookstoreAPI::Handlers::Reviews;

use strict;
use warnings;
use parent 'PAGI::OpenAPI::Handler';
use Future::AsyncAwait;

async sub list {
    my ($self, $c) = @_;

    my $book_id = $c->path_param('id');
    my $book = $c->db->find_book($book_id);

    return await $c->not_found("Book $book_id not found") unless $book;

    my $reviews = $c->db->reviews_for_book($book_id);
    my $avg = $c->db->average_rating($book_id);

    await $c->json({
        reviews        => $reviews,
        average_rating => $avg,
    });
}

async sub create {
    my ($self, $c) = @_;

    my $token = $c->bearer_token;
    my $user = $c->auth->verify_token($token);
    return await $c->unauthorized unless $user;

    my $book_id = $c->path_param('id');
    my $book = $c->db->find_book($book_id);
    return await $c->not_found("Book $book_id not found") unless $book;

    my $data = await $c->request_json;
    $data->{user} = $user;

    my $review = $c->db->create_review($book_id, $data);
    await $c->status(201)->json($review);
}

1;

__END__

=head1 NAME

BookstoreAPI::Handlers::Reviews - Book review operations

=head1 METHODS

=head2 list

    GET /books/{id}/reviews

Get all reviews for a book.

=head2 create

    POST /books/{id}/reviews

Create a review for a book. Requires authentication.

=cut
