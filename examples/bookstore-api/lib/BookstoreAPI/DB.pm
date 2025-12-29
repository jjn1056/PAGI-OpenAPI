package BookstoreAPI::DB;

use strict;
use warnings;
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
    my $tolkien   = $self->create_author({ name => 'J.R.R. Tolkien', bio => 'English writer and philologist' });
    my $king      = $self->create_author({ name => 'Stephen King', bio => 'American author of horror and suspense' });
    my $asimov    = $self->create_author({ name => 'Isaac Asimov', bio => 'Prolific science fiction author' });
    my $christie  = $self->create_author({ name => 'Agatha Christie', bio => 'Queen of mystery fiction' });
    my $orwell    = $self->create_author({ name => 'George Orwell', bio => 'English novelist and essayist' });
    my $austen    = $self->create_author({ name => 'Jane Austen', bio => 'English novelist known for romantic fiction' });
    my $dickens   = $self->create_author({ name => 'Charles Dickens', bio => 'Victorian era novelist' });
    my $hemingway = $self->create_author({ name => 'Ernest Hemingway', bio => 'American novelist and journalist' });

    # Books - Tolkien
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
    $self->create_book({
        title          => 'The Silmarillion',
        author_id      => $tolkien->{id},
        genre          => 'fiction',
        isbn           => '9780618391110',
        published_year => 1977,
        price          => 16.99,
    });

    # Books - Stephen King
    my $shining = $self->create_book({
        title          => 'The Shining',
        author_id      => $king->{id},
        genre          => 'mystery',
        isbn           => '9780307743657',
        published_year => 1977,
        price          => 16.99,
    });
    $self->create_book({
        title          => 'It',
        author_id      => $king->{id},
        genre          => 'mystery',
        isbn           => '9781501142970',
        published_year => 1986,
        price          => 19.99,
    });
    $self->create_book({
        title          => 'The Stand',
        author_id      => $king->{id},
        genre          => 'fiction',
        isbn           => '9780307947307',
        published_year => 1978,
        price          => 21.99,
    });

    # Books - Asimov
    my $foundation = $self->create_book({
        title          => 'Foundation',
        author_id      => $asimov->{id},
        genre          => 'sci-fi',
        isbn           => '9780553293357',
        published_year => 1951,
        price          => 17.00,
    });
    $self->create_book({
        title          => 'I, Robot',
        author_id      => $asimov->{id},
        genre          => 'sci-fi',
        isbn           => '9780553382563',
        published_year => 1950,
        price          => 15.99,
    });
    $self->create_book({
        title          => 'Foundation and Empire',
        author_id      => $asimov->{id},
        genre          => 'sci-fi',
        isbn           => '9780553293371',
        published_year => 1952,
        price          => 16.99,
    });

    # Books - Agatha Christie
    $self->create_book({
        title          => 'Murder on the Orient Express',
        author_id      => $christie->{id},
        genre          => 'mystery',
        isbn           => '9780062693662',
        published_year => 1934,
        price          => 14.99,
    });
    $self->create_book({
        title          => 'And Then There Were None',
        author_id      => $christie->{id},
        genre          => 'mystery',
        isbn           => '9780062073488',
        published_year => 1939,
        price          => 14.99,
    });
    $self->create_book({
        title          => 'The ABC Murders',
        author_id      => $christie->{id},
        genre          => 'mystery',
        isbn           => '9780062073587',
        published_year => 1936,
        price          => 13.99,
    });

    # Books - George Orwell
    $self->create_book({
        title          => '1984',
        author_id      => $orwell->{id},
        genre          => 'fiction',
        isbn           => '9780451524935',
        published_year => 1949,
        price          => 12.99,
    });
    $self->create_book({
        title          => 'Animal Farm',
        author_id      => $orwell->{id},
        genre          => 'fiction',
        isbn           => '9780451526342',
        published_year => 1945,
        price          => 10.99,
    });

    # Books - Jane Austen
    $self->create_book({
        title          => 'Pride and Prejudice',
        author_id      => $austen->{id},
        genre          => 'romance',
        isbn           => '9780141439518',
        published_year => 1813,
        price          => 9.99,
    });
    $self->create_book({
        title          => 'Sense and Sensibility',
        author_id      => $austen->{id},
        genre          => 'romance',
        isbn           => '9780141439662',
        published_year => 1811,
        price          => 9.99,
    });
    $self->create_book({
        title          => 'Emma',
        author_id      => $austen->{id},
        genre          => 'romance',
        isbn           => '9780141439587',
        published_year => 1815,
        price          => 10.99,
    });

    # Books - Charles Dickens
    $self->create_book({
        title          => 'A Tale of Two Cities',
        author_id      => $dickens->{id},
        genre          => 'fiction',
        isbn           => '9780141439600',
        published_year => 1859,
        price          => 11.99,
    });
    $self->create_book({
        title          => 'Great Expectations',
        author_id      => $dickens->{id},
        genre          => 'fiction',
        isbn           => '9780141439563',
        published_year => 1861,
        price          => 12.99,
    });
    $self->create_book({
        title          => 'Oliver Twist',
        author_id      => $dickens->{id},
        genre          => 'fiction',
        isbn           => '9780141439747',
        published_year => 1838,
        price          => 10.99,
    });

    # Books - Ernest Hemingway
    $self->create_book({
        title          => 'The Old Man and the Sea',
        author_id      => $hemingway->{id},
        genre          => 'fiction',
        isbn           => '9780684801223',
        published_year => 1952,
        price          => 13.99,
    });
    $self->create_book({
        title          => 'A Farewell to Arms',
        author_id      => $hemingway->{id},
        genre          => 'fiction',
        isbn           => '9780684801469',
        published_year => 1929,
        price          => 14.99,
    });
    $self->create_book({
        title          => 'For Whom the Bell Tolls',
        author_id      => $hemingway->{id},
        genre          => 'fiction',
        isbn           => '9780684803357',
        published_year => 1940,
        price          => 16.99,
    });

    # Reviews
    $self->create_review($lotr->{id}, { user => 'reader1', rating => 5, text => 'A masterpiece of fantasy literature!' });
    $self->create_review($lotr->{id}, { user => 'reader2', rating => 5, text => 'Changed my life. Read it three times.' });
    $self->create_review($hobbit->{id}, { user => 'reader3', rating => 4, text => 'Great introduction to Middle-earth.' });
    $self->create_review($shining->{id}, { user => 'reader1', rating => 5, text => 'Terrifying and brilliant.' });
    $self->create_review($foundation->{id}, { user => 'reader4', rating => 5, text => 'The best sci-fi series ever written.' });
}

# ============================================================
# Books
# ============================================================

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

# ============================================================
# Authors
# ============================================================

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

# ============================================================
# Reviews
# ============================================================

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

__END__

=head1 NAME

BookstoreAPI::DB - In-memory database for bookstore demo

=head1 DESCRIPTION

Simple in-memory storage for books, authors, and reviews.
In production, use a real database.

=cut
