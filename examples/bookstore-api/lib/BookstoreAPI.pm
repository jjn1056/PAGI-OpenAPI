package BookstoreAPI;

use strict;
use warnings;
use parent 'PAGI::OpenAPI';
use Future::AsyncAwait;

# Schema path is relative to home directory (auto-detected)
sub openapi_schema { 'schema.yaml' }

# Disable validation for this demo (faster startup)
sub enable_validation { 0 }

# Middleware stack applied via run_if_script
sub middleware {
    return (
        # Log all requests
        'PAGI::Middleware::AccessLog',
        # Enable CORS for API access
        ['PAGI::Middleware::CORS', origins => ['*']],
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

    # App-scoped: database (returns object, persists across requests)
    $self->service(db => sub {
        my ($app) = @_;
        require BookstoreAPI::DB;
        my $db = BookstoreAPI::DB->new;
        $db->seed_data;
        return $db;
    });

    # App-scoped: auth service (returns object)
    $self->service(auth => sub {
        my ($app) = @_;
        require BookstoreAPI::Auth;
        return BookstoreAPI::Auth->new(secret => 'demo-secret-key');
    });
}

async sub on_startup {
    my ($self, $scope) = @_;
    print "Bookstore API started!\n";
    print "  Home: " . $self->home . "\n";
    print "  Web App: http://localhost:5000/\n";
    print "  API Docs: http://localhost:5000/docs\n";
}

# Make this module directly runnable
__PACKAGE__->run_if_script;

__END__

=head1 NAME

BookstoreAPI - Example bookstore API using PAGI::OpenAPI

=head1 SYNOPSIS

    # Run directly (no app.pl needed)
    pagi-server -Ilib ./lib/BookstoreAPI.pm --port 5000

    # Or with app.pl wrapper
    pagi-server --app app.pl --port 5000

    # Visit http://localhost:5000/docs for Swagger UI

=head1 DESCRIPTION

This is an example PAGI::OpenAPI application demonstrating:

=over 4

=item * Service pattern with return-type-determines-scope

=item * Multiple handler classes (Books, Authors, Reviews, Auth)

=item * Bearer token authentication

=item * Resource relationships

=item * Pagination

=item * Proper lib/ directory structure

=back

=cut
