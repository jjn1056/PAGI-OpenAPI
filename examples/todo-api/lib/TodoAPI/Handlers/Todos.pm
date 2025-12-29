package TodoAPI::Handlers::Todos;

use strict;
use warnings;
use parent 'PAGI::OpenAPI::Handler';
use Future::AsyncAwait;

async sub list {
    my ($self, $c) = @_;

    my %filter;
    if (defined(my $completed = $c->query('completed'))) {
        # Convert string "true"/"false" to boolean
        $filter{completed} = ($completed eq 'true' || $completed eq '1') ? 1 : 0;
    }
    $filter{limit} = $c->query('limit');

    my $todos = $c->todos->all(%filter);
    my $total = $c->todos->total;

    # Add HATEOAS links to each todo
    for my $todo (@$todos) {
        $todo->{_links} = {
            self     => $c->uri_for('Todos.get', { id => $todo->{id} }),
            update   => $c->uri_for('Todos.update', { id => $todo->{id} }),
            delete   => $c->uri_for('Todos.delete', { id => $todo->{id} }),
            complete => $c->uri_for('Todos.complete', { id => $todo->{id} }),
        };
    }

    await $c->json({
        todos  => $todos,
        total  => $total,
        _links => {
            self   => $c->uri_for('Todos.list'),
            create => $c->uri_for('Todos.create'),
        },
    });
}

async sub get {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $todo = $c->todos->find($id);

    return await $c->not_found("Todo $id not found") unless $todo;

    # Add HATEOAS links
    $todo->{_links} = {
        self     => $c->uri_for('Todos.get', { id => $id }),
        list     => $c->uri_for('Todos.list'),
        update   => $c->uri_for('Todos.update', { id => $id }),
        delete   => $c->uri_for('Todos.delete', { id => $id }),
        complete => $c->uri_for('Todos.complete', { id => $id }),
    };

    await $c->json($todo);
}

async sub create {
    my ($self, $c) = @_;

    my $data = await $c->request_json;
    my $todo = $c->todos->create($data);

    # Add Location header and HATEOAS links
    my $location = $c->uri_for('Todos.get', { id => $todo->{id} });
    $todo->{_links} = {
        self     => $location,
        list     => $c->uri_for('Todos.list'),
        update   => $c->uri_for('Todos.update', { id => $todo->{id} }),
        delete   => $c->uri_for('Todos.delete', { id => $todo->{id} }),
        complete => $c->uri_for('Todos.complete', { id => $todo->{id} }),
    };

    await $c->status(201)->set_header('Location' => $location)->json($todo);
}

async sub update {
    my ($self, $c) = @_;

    my $id = $c->path_param('id');
    my $data = await $c->request_json;
    my $todo = $c->todos->update($id, $data);

    return await $c->not_found("Todo $id not found") unless $todo;

    # Add HATEOAS links
    $todo->{_links} = {
        self     => $c->uri_for('Todos.get', { id => $id }),
        list     => $c->uri_for('Todos.list'),
        delete   => $c->uri_for('Todos.delete', { id => $id }),
        complete => $c->uri_for('Todos.complete', { id => $id }),
    };

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

    # Add HATEOAS links
    $todo->{_links} = {
        self   => $c->uri_for('Todos.get', { id => $id }),
        list   => $c->uri_for('Todos.list'),
        delete => $c->uri_for('Todos.delete', { id => $id }),
    };

    await $c->json($todo);
}

1;

__END__

=head1 NAME

TodoAPI::Handlers::Todos - Todo CRUD handlers

=head1 METHODS

=head2 list

    GET /todos

List todos with optional filtering.

=head2 get

    GET /todos/{id}

Get a single todo by ID.

=head2 create

    POST /todos

Create a new todo.

=head2 update

    PUT /todos/{id}

Update an existing todo.

=head2 delete

    DELETE /todos/{id}

Delete a todo.

=head2 complete

    POST /todos/{id}/complete

Mark a todo as completed.

=cut
