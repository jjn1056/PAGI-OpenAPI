package TodoAPI::Store;

use strict;
use warnings;
use POSIX qw(strftime);

sub new {
    my ($class, $items) = @_;
    my $next_id = 1;
    for my $item (@{ $items // [] }) {
        $next_id = $item->{id} + 1 if $item->{id} >= $next_id;
    }
    return bless {
        items   => $items // [],
        next_id => $next_id,
    }, $class;
}

sub all {
    my ($self, %filter) = @_;
    my @items = @{$self->{items}};

    if (defined $filter{completed}) {
        my $want = $filter{completed} ? 1 : 0;
        @items = grep { $_->{completed} == $want } @items;
    }

    if ($filter{limit}) {
        @items = @items[0 .. ($filter{limit} - 1)] if @items > $filter{limit};
    }

    return \@items;
}

sub find {
    my ($self, $id) = @_;
    my ($item) = grep { $_->{id} == $id } @{$self->{items}};
    return $item;
}

sub create {
    my ($self, $data) = @_;
    my $item = {
        id          => $self->{next_id}++,
        title       => $data->{title},
        description => $data->{description} // '',
        completed   => $data->{completed} ? 1 : 0,
        created_at  => _now(),
    };
    push @{$self->{items}}, $item;
    return $item;
}

sub update {
    my ($self, $id, $data) = @_;
    my $item = $self->find($id) or return;
    $item->{title}       = $data->{title} if exists $data->{title};
    $item->{description} = $data->{description} if exists $data->{description};
    if (exists $data->{completed}) {
        my $was_complete = $item->{completed};
        $item->{completed} = $data->{completed} ? 1 : 0;
        if ($item->{completed} && !$was_complete) {
            $item->{completed_at} = _now();
        }
    }
    return $item;
}

sub delete {
    my ($self, $id) = @_;
    my $before = @{$self->{items}};
    @{$self->{items}} = grep { $_->{id} != $id } @{$self->{items}};
    return @{$self->{items}} < $before;
}

sub total { scalar @{shift->{items}} }

sub _now { strftime('%Y-%m-%dT%H:%M:%SZ', gmtime) }

1;

__END__

=head1 NAME

TodoAPI::Store - In-memory todo storage

=head1 SYNOPSIS

    my $store = TodoAPI::Store->new([
        { id => 1, title => 'Task 1', completed => 0 },
    ]);

    my $todos = $store->all(completed => 0, limit => 10);
    my $todo = $store->find(1);
    my $new = $store->create({ title => 'New task' });

=cut
