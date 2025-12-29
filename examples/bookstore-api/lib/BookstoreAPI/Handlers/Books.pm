package BookstoreAPI::Handlers::Books;

use strict;
use warnings;
use parent 'PAGI::OpenAPI::Handler';
use Future::AsyncAwait;

# Helper to check auth
sub _require_auth {
    my ($self, $c) = @_;
    my $token = $c->bearer_token;
    return $c->auth->verify_token($token);
}

async sub list {
    my ($self, $c) = @_;

    my $result = $c->db->list_books(
        author_id => $c->query('author_id'),
        genre     => $c->query('genre'),
        page      => $c->query('page') // 1,
        per_page  => $c->query('per_page') // 10,
    );

    await $c->json($result);
}

async sub get {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $book = $c->db->find_book($id);

    return await $c->not_found("Book $id not found") unless $book;

    # Include author and reviews
    my $author = $c->db->find_author($book->{author_id});
    my $reviews = $c->db->reviews_for_book($id);
    my $avg_rating = $c->db->average_rating($id);

    await $c->json({
        %$book,
        author         => $author,
        reviews        => $reviews,
        average_rating => $avg_rating,
    });
}

async sub create {
    my ($self, $c) = @_;

    my $user = $self->_require_auth($c);
    return await $c->unauthorized unless $user;

    my $data = await $c->request_json;

    # Verify author exists
    my $author = $c->db->find_author($data->{author_id});
    return await $c->bad_request("Author not found") unless $author;

    my $book = $c->db->create_book($data);
    await $c->status(201)->json($book);
}

async sub update {
    my ($self, $c) = @_;

    my $user = $self->_require_auth($c);
    return await $c->unauthorized unless $user;

    my $id = $c->path_param('id');
    my $data = await $c->request_json;
    my $book = $c->db->update_book($id, $data);

    return await $c->not_found("Book $id not found") unless $book;
    await $c->json($book);
}

async sub delete {
    my ($self, $c) = @_;

    my $user = $self->_require_auth($c);
    return await $c->unauthorized unless $user;

    my $id = $c->path_param('id');
    my $deleted = $c->db->delete_book($id);

    return await $c->not_found("Book $id not found") unless $deleted;
    await $c->status(204)->send;
}

1;

__END__

=head1 NAME

BookstoreAPI::Handlers::Books - Book CRUD operations

=head1 METHODS

=head2 list

    GET /books

List books with optional filtering by author_id and genre.
Supports pagination via page and per_page query params.

=head2 get

    GET /books/{id}

Get a book by ID, including author and reviews.

=head2 create

    POST /books

Create a new book. Requires authentication.

=head2 update

    PUT /books/{id}

Update a book. Requires authentication.

=head2 delete

    DELETE /books/{id}

Delete a book. Requires authentication.

=cut
