package BookstoreAPI::Handlers::Authors;

use strict;
use warnings;
use parent 'PAGI::OpenAPI::Handler';
use Future::AsyncAwait;

async sub list {
    my ($self, $c) = @_;

    my $authors = $c->db->list_authors;
    await $c->json({ authors => $authors });
}

async sub get {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $author = $c->db->find_author($id);

    return await $c->not_found("Author $id not found") unless $author;

    my $books = $c->db->books_by_author($id);
    my $book_count = scalar @$books;

    await $c->json({
        %$author,
        book_count => $book_count,
        books      => $books,
    });
}

async sub create {
    my ($self, $c) = @_;

    my $token = $c->bearer_token;
    my $user = $c->auth->verify_token($token);
    return await $c->unauthorized unless $user;

    my $data = await $c->request_json;
    my $author = $c->db->create_author($data);

    await $c->status(201)->json($author);
}

1;

__END__

=head1 NAME

BookstoreAPI::Handlers::Authors - Author operations

=head1 METHODS

=head2 list

    GET /authors

List all authors with book counts.

=head2 get

    GET /authors/{id}

Get an author by ID, including their books.

=head2 create

    POST /authors

Create a new author. Requires authentication.

=cut
