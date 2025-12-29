#!/usr/bin/env perl
# Todo API Example
#
# Run with: pagi-server --app app.pl --port 5000
# Then visit: http://localhost:5000/docs

use strict;
use warnings;
use FindBin;
use File::Spec;

# ============================================================
# Main Application
# ============================================================

package TodoAPI;
use parent 'PAGI::OpenAPI';
use Future::AsyncAwait;

sub openapi_schema {
    File::Spec->catfile($FindBin::Bin, 'schema.yaml');
}

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
        todos => $state->{todos},
    };
}

async sub on_startup {
    my ($self, $scope) = @_;

    # In-memory todo storage with sample data
    $self->state->{todos} = TodoAPI::Store->new([
        {
            id          => 1,
            title       => 'Learn PAGI::OpenAPI',
            description => 'Read the docs and build an app',
            completed   => 0,
            created_at  => '2025-01-01T10:00:00Z',
        },
        {
            id          => 2,
            title       => 'Build something awesome',
            description => 'Create a real-world API',
            completed   => 0,
            created_at  => '2025-01-01T11:00:00Z',
        },
    ]);

    print "Todo API started!\n";
    print "  Web App: http://localhost:5000/\n";
    print "  API Docs: http://localhost:5000/docs\n";
}

1;

# ============================================================
# In-Memory Store
# ============================================================

package TodoAPI::Store;
use POSIX qw(strftime);

sub new {
    my ($class, $items) = @_;
    my $next_id = 1;
    for my $item (@$items) {
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

# ============================================================
# Handlers
# ============================================================

package TodoAPI::Handlers::Todos;
use parent 'PAGI::OpenAPI::Handler';
use Future::AsyncAwait;

async sub list {
    my ($self, $c) = @_;

    my %filter;
    $filter{completed} = $c->query('completed') if defined $c->query('completed');
    $filter{limit}     = $c->query('limit');

    my $todos = $c->todos->all(%filter);
    my $total = $c->todos->total;

    await $c->json({
        todos => $todos,
        total => $total,
    });
}

async sub get {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $todo = $c->todos->find($id);

    return await $c->not_found("Todo $id not found") unless $todo;
    await $c->json($todo);
}

async sub create {
    my ($self, $c) = @_;

    my $data = await $c->request_json;
    my $todo = $c->todos->create($data);

    await $c->status(201)->json($todo);
}

async sub update {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $data = await $c->request_json;
    my $todo = $c->todos->update($id, $data);

    return await $c->not_found("Todo $id not found") unless $todo;
    await $c->json($todo);
}

async sub delete {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $deleted = $c->todos->delete($id);

    return await $c->not_found("Todo $id not found") unless $deleted;
    await $c->status(204)->send;
}

async sub complete {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $todo = $c->todos->update($id, { completed => 1 });

    return await $c->not_found("Todo $id not found") unless $todo;
    await $c->json($todo);
}

1;

# ============================================================
# Return app for pagi-server
# ============================================================

TodoAPI->to_app;
