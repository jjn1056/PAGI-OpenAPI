#!/usr/bin/env perl
# Bookstore API Example
#
# Demonstrates:
# - Multiple handler classes (Books, Authors, Reviews, Auth)
# - Bearer token authentication
# - Resource relationships
# - Pagination helpers
# - Custom auth helper
#
# Run with: pagi-server --app app.pl --port 5000
# Then visit: http://localhost:5000/docs
#
# Get a token:
#   curl -X POST http://localhost:5000/auth/token \
#     -H "Content-Type: application/json" \
#     -d '{"username":"demo","password":"demo"}'
#
# Use it:
#   curl http://localhost:5000/books \
#     -H "Authorization: Bearer <token>"

use strict;
use warnings;
use lib 'lib';
use FindBin;
use File::Spec;

# ============================================================
# Main Application
# ============================================================

package BookstoreAPI;
use parent 'PAGI::OpenAPI';
use Future::AsyncAwait;

sub openapi_schema {
    File::Spec->catfile($FindBin::Bin, 'schema.yaml');
}

# Disable validation for this demo (faster startup)
sub enable_validation { 0 }

# Serve the web frontend
sub setup_routes {
    my ($self, $r) = @_;

    $r->get('/' => async sub {
        my ($req, $res) = @_;
        my $html_path = File::Spec->catfile($FindBin::Bin, 'public', 'index.html');
        await $res->send_file($html_path);
    });
}

sub build_helpers {
    my ($self, $state) = @_;
    return {
        db   => $state->{db},
        auth => BookstoreAPI::Auth->new(secret => 'demo-secret-key'),
    };
}

async sub on_startup {
    my ($self, $scope) = @_;

    # Initialize in-memory database
    $self->state->{db} = BookstoreAPI::DB->new;
    $self->state->{db}->seed_data;

    print "Bookstore API started!\n";
    print "  Web App: http://localhost:5000/\n";
    print "  API Docs: http://localhost:5000/docs\n";
}

1;

# ============================================================
# Simple Auth Helper
# ============================================================

package BookstoreAPI::Auth;
use Digest::SHA qw(sha256_hex);
use POSIX qw(strftime);

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

# ============================================================
# In-Memory Database
# ============================================================

package BookstoreAPI::DB;
use POSIX qw(strftime);

sub new {
    my $class = shift;
    return bless {
        books    => [],
        authors  => [],
        reviews  => [],
        next_id  => { books => 1, authors => 1, reviews => 1 },
    }, $class;
}

sub seed_data {
    my $self = shift;

    # Authors
    my $tolkien = $self->create_author({ name => 'J.R.R. Tolkien', bio => 'English writer and philologist' });
    my $king    = $self->create_author({ name => 'Stephen King', bio => 'American author of horror and suspense' });
    my $asimov  = $self->create_author({ name => 'Isaac Asimov', bio => 'Prolific science fiction author' });

    # Books
    my $lotr = $self->create_book({
        title          => 'The Lord of the Rings',
        author_id      => $tolkien->{id},
        genre          => 'fiction',
        isbn           => '9780544003415',
        published_year => 1954,
        price          => 29.99,
    });

    my $hobbit = $self->create_book({
        title          => 'The Hobbit',
        author_id      => $tolkien->{id},
        genre          => 'fiction',
        isbn           => '9780547928227',
        published_year => 1937,
        price          => 14.99,
    });

    my $shining = $self->create_book({
        title          => 'The Shining',
        author_id      => $king->{id},
        genre          => 'mystery',
        isbn           => '9780307743657',
        published_year => 1977,
        price          => 16.99,
    });

    my $foundation = $self->create_book({
        title          => 'Foundation',
        author_id      => $asimov->{id},
        genre          => 'sci-fi',
        isbn           => '9780553293357',
        published_year => 1951,
        price          => 17.00,
    });

    # Reviews
    $self->create_review($lotr->{id}, { user => 'reader1', rating => 5, text => 'A masterpiece of fantasy literature!' });
    $self->create_review($lotr->{id}, { user => 'reader2', rating => 5, text => 'Changed my life. Read it three times.' });
    $self->create_review($hobbit->{id}, { user => 'reader3', rating => 4, text => 'Great introduction to Middle-earth.' });
    $self->create_review($shining->{id}, { user => 'reader1', rating => 5, text => 'Terrifying and brilliant.' });
    $self->create_review($foundation->{id}, { user => 'reader4', rating => 5, text => 'The best sci-fi series ever written.' });
}

# Books
sub list_books {
    my ($self, %opts) = @_;
    my @books = @{$self->{books}};

    @books = grep { $_->{author_id} == $opts{author_id} } @books if $opts{author_id};
    @books = grep { $_->{genre} eq $opts{genre} } @books if $opts{genre};

    my $total = scalar @books;
    my $page = $opts{page} // 1;
    my $per_page = $opts{per_page} // 10;
    my $offset = ($page - 1) * $per_page;

    @books = splice(@books, $offset, $per_page);

    return {
        books => \@books,
        pagination => {
            page        => $page,
            per_page    => $per_page,
            total       => $total,
            total_pages => int(($total + $per_page - 1) / $per_page),
        },
    };
}

sub find_book {
    my ($self, $id) = @_;
    my ($book) = grep { $_->{id} == $id } @{$self->{books}};
    return $book;
}

sub create_book {
    my ($self, $data) = @_;
    my $book = {
        id             => $self->{next_id}{books}++,
        title          => $data->{title},
        author_id      => $data->{author_id},
        genre          => $data->{genre},
        isbn           => $data->{isbn} // '',
        published_year => $data->{published_year},
        price          => $data->{price} // 0,
    };
    push @{$self->{books}}, $book;
    return $book;
}

sub update_book {
    my ($self, $id, $data) = @_;
    my $book = $self->find_book($id) or return;
    for my $key (qw(title author_id genre isbn published_year price)) {
        $book->{$key} = $data->{$key} if exists $data->{$key};
    }
    return $book;
}

sub delete_book {
    my ($self, $id) = @_;
    my $before = @{$self->{books}};
    @{$self->{books}} = grep { $_->{id} != $id } @{$self->{books}};
    return @{$self->{books}} < $before;
}

# Authors
sub list_authors {
    my $self = shift;
    return [ map {
        my $author = { %$_ };
        $author->{book_count} = scalar grep { $_->{author_id} == $author->{id} } @{$self->{books}};
        $author;
    } @{$self->{authors}} ];
}

sub find_author {
    my ($self, $id) = @_;
    my ($author) = grep { $_->{id} == $id } @{$self->{authors}};
    return $author;
}

sub create_author {
    my ($self, $data) = @_;
    my $author = {
        id   => $self->{next_id}{authors}++,
        name => $data->{name},
        bio  => $data->{bio} // '',
    };
    push @{$self->{authors}}, $author;
    return $author;
}

sub books_by_author {
    my ($self, $author_id) = @_;
    return [ grep { $_->{author_id} == $author_id } @{$self->{books}} ];
}

# Reviews
sub reviews_for_book {
    my ($self, $book_id) = @_;
    return [ grep { $_->{book_id} == $book_id } @{$self->{reviews}} ];
}

sub average_rating {
    my ($self, $book_id) = @_;
    my @reviews = grep { $_->{book_id} == $book_id } @{$self->{reviews}};
    return 0 unless @reviews;
    my $sum = 0;
    $sum += $_->{rating} for @reviews;
    return sprintf("%.1f", $sum / @reviews) + 0;
}

sub create_review {
    my ($self, $book_id, $data) = @_;
    my $review = {
        id         => $self->{next_id}{reviews}++,
        book_id    => $book_id,
        user       => $data->{user},
        rating     => $data->{rating},
        text       => $data->{text},
        created_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    };
    push @{$self->{reviews}}, $review;
    return $review;
}

1;

# ============================================================
# Auth Handler
# ============================================================

package BookstoreAPI::Handlers::Auth;
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

# ============================================================
# Books Handler
# ============================================================

package BookstoreAPI::Handlers::Books;
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

# ============================================================
# Authors Handler
# ============================================================

package BookstoreAPI::Handlers::Authors;
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

# ============================================================
# Reviews Handler
# ============================================================

package BookstoreAPI::Handlers::Reviews;
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

# ============================================================
# Return app for pagi-server
# ============================================================

BookstoreAPI->to_app;
