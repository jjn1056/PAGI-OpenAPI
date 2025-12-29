package PAGI::OpenAPI::Handler;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        app => $args{app},
    }, $class;
}

sub app { shift->{app} }

1;

__END__

=head1 NAME

PAGI::OpenAPI::Handler - Base class for OpenAPI handler classes

=head1 SYNOPSIS

    package MyApp::Handlers::Todos;
    use parent 'PAGI::OpenAPI::Handler';
    use Future::AsyncAwait;

    async sub list {
        my ($self, $c) = @_;

        my $todos = await $c->pg->query_all_f('SELECT * FROM todos');
        await $c->json({ todos => $todos });
    }

    async sub get {
        my ($self, $c) = @_;

        my $id = $c->path_param('id');
        my $todo = await $c->pg->query_one_f(
            'SELECT * FROM todos WHERE id = $1', $id
        );

        return await $c->not_found('Todo not found') unless $todo;
        await $c->json($todo);
    }

    1;

=head1 DESCRIPTION

PAGI::OpenAPI::Handler is a simple base class for handler classes used with
L<PAGI::OpenAPI>. Handler methods receive a L<PAGI::OpenAPI::Context> object
as their second argument, providing access to the request, response, and
application helpers.

=head1 CONSTRUCTOR

=head2 new

    my $handler = MyApp::Handlers::Todos->new(app => $app);

Creates a new handler instance. Called automatically by PAGI::OpenAPI when
the handler is first needed.

=over 4

=item app

Reference to the parent PAGI::OpenAPI application instance.

=back

=head1 METHODS

=head2 app

    my $app = $self->app;

Returns the parent application instance.

=head1 HANDLER METHODS

Handler methods are defined in your subclass and mapped from OpenAPI
C<operationId> values. The method signature is:

    async sub method_name {
        my ($self, $c) = @_;
        # ...
    }

Where C<$c> is a L<PAGI::OpenAPI::Context> object providing:

=over 4

=item * Request data: C<< $c->path_param('id') >>, C<< $c->query('page') >>,
C<< await $c->json >>

=item * Response methods: C<< await $c->json($data) >>,
C<< await $c->not_found >>

=item * Helpers: C<< $c->pg >>, C<< $c->redis >>, etc. (as defined in your app)

=back

=head1 OPERATION ID MAPPING

OpenAPI operationIds are mapped to handler classes and methods using dot
notation:

    operationId: Todos.list    -> MyApp::Handlers::Todos->list($c)
    operationId: Todos.create  -> MyApp::Handlers::Todos->create($c)
    operationId: Users.get     -> MyApp::Handlers::Users->get($c)

The handler namespace is configured in your PAGI::OpenAPI subclass via
C<handler_namespace()>.

=head1 SEE ALSO

L<PAGI::OpenAPI>, L<PAGI::OpenAPI::Context>

=cut
