package TodoAPI;

use strict;
use warnings;
use parent 'PAGI::OpenAPI';
use Future::AsyncAwait;

# Schema path is relative to home directory (auto-detected)
sub openapi_schema { 'schema.yaml' }

# Disable validation for this demo
sub enable_validation { 0 }

# Middleware stack applied via run_if_script
sub middleware {
    return (
        'PAGI::Middleware::AccessLog',
    );
}

# Serve the web frontend
sub setup_routes {
    my ($self, $r) = @_;
    my $app = $self;  # Capture for closure

    $r->get('/' => async sub {
        my ($req, $res) = @_;
        my $html_path = $app->home_path('public', 'index.html');
        await $res->send_file($html_path->stringify);
    });
}

# Service registration - return type determines scope
sub setup_services {
    my ($self) = @_;

    # App-scoped: returns object (persists across requests)
    $self->service(todos => sub {
        my ($app) = @_;
        require TodoAPI::Store;
        return TodoAPI::Store->new([
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
    });
}

async sub on_startup {
    my ($self, $scope) = @_;
    print "Todo API started!\n";
    print "  Home: " . $self->home . "\n";
    print "  Web App: http://localhost:5000/\n";
    print "  API Docs: http://localhost:5000/docs\n";
}

# Make this module directly runnable
__PACKAGE__->run_if_script;

__END__

=head1 NAME

TodoAPI - Example todo API using PAGI::OpenAPI

=head1 SYNOPSIS

    # Run directly (no app.pl needed)
    pagi-server -Ilib -I../../lib ./lib/TodoAPI.pm --port 5000

    # Or with app.pl wrapper
    pagi-server --app app.pl --port 5000

    # Visit http://localhost:5000/docs for Swagger UI

=head1 DESCRIPTION

This is an example PAGI::OpenAPI application demonstrating:

=over 4

=item * Service pattern with return-type-determines-scope

=item * Direct $c->service_name access via AUTOLOAD

=item * home() for automatic app directory detection

=item * Proper lib/ directory structure

=back

=cut
