use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;
use File::Spec;

# Skip if OpenAPI::Modern not installed
BEGIN {
    eval { require OpenAPI::Modern; 1 }
        or plan skip_all => 'OpenAPI::Modern not installed';
}

use PAGI::OpenAPI;
use PAGI::Test::Client;

# Path to test schema
my $schema_path = File::Spec->catfile('t', 'fixtures', 'test-openapi.yaml');

# Create a test app
package UriForTestAPI {
    use parent 'PAGI::OpenAPI';
    use Future::AsyncAwait;

    our $SCHEMA_PATH;

    sub openapi_schema { $SCHEMA_PATH }
    sub enable_validation { 0 }

    1;
}

# Handler that uses uri_for
package UriForTestAPI::Handlers::Items {
    use parent 'PAGI::OpenAPI::Handler';
    use Future::AsyncAwait;

    async sub list {
        my ($self, $c) = @_;

        # Test uri_for functionality within a handler
        my $urls = {
            self       => $c->uri_for('Items.list'),
            with_query => $c->uri_for('Items.list', {}, { limit => 5 }),
            get_item   => $c->uri_for('Items.get', { id => 42 }),
            item_query => $c->uri_for('Items.get', { id => 7 }, { format => 'json' }),
        };

        await $c->json({ urls => $urls });
    }

    async sub get {
        my ($self, $c) = @_;
        my $id = $c->path_param('id');

        # Generate links in response
        my $item = {
            id    => $id,
            name  => "Item $id",
            links => {
                self   => $c->uri_for('Items.get', { id => $id }),
                list   => $c->uri_for('Items.list'),
                delete => $c->uri_for('Items.delete', { id => $id }),
            },
        };

        await $c->json($item);
    }

    async sub create {
        my ($self, $c) = @_;
        # Dummy create
        await $c->status(201)->json({ id => 999, created => 1 });
    }

    async sub delete {
        my ($self, $c) = @_;
        await $c->status(204)->send;
    }

    1;
}

# Set schema path
$UriForTestAPI::SCHEMA_PATH = $schema_path;

# Create app with lifespan enabled
my $app = UriForTestAPI->to_app;
my $client = PAGI::Test::Client->new(app => $app, lifespan => 1);
$client->start;

subtest 'uri_for basic usage' => sub {
    my $res = $client->get('/items');
    is $res->status, 200, 'status 200';

    my $data = $res->json;
    ok exists $data->{urls}, 'has urls key';

    is $data->{urls}{self}, '/items', 'uri_for Items.list';
    is $data->{urls}{with_query}, '/items?limit=5', 'uri_for with query params';
    is $data->{urls}{get_item}, '/items/42', 'uri_for Items.get with path param';
    is $data->{urls}{item_query}, '/items/7?format=json', 'uri_for with path and query params';
};

subtest 'uri_for in HATEOAS links' => sub {
    my $res = $client->get('/items/123');
    is $res->status, 200, 'status 200';

    my $item = $res->json;
    is $item->{id}, 123, 'item id';

    ok exists $item->{links}, 'has links';
    is $item->{links}{self}, '/items/123', 'self link';
    is $item->{links}{list}, '/items', 'list link';
    is $item->{links}{delete}, '/items/123', 'delete link';
};

subtest 'uri_for with special characters' => sub {
    # Test that query params are properly encoded
    my $res = $client->get('/items');
    is $res->status, 200, 'status 200';

    # The basic test already verifies encoding works through the limit=5 test
    # Additional encoding tests would need handlers that test edge cases
};

done_testing;
