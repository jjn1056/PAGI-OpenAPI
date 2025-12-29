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
package TestAPI {
    use parent 'PAGI::OpenAPI';
    use Future::AsyncAwait;

    our $SCHEMA_PATH;

    sub openapi_schema { $SCHEMA_PATH }
    sub enable_validation { 0 }  # Disable for basic tests

    sub build_helpers {
        my ($self, $state) = @_;
        return {
            items => $state->{items},
        };
    }

    async sub on_startup {
        my ($self, $scope) = @_;
        # In-memory items storage
        $self->state->{items} = [
            { id => 1, name => 'Item 1', description => 'First item' },
            { id => 2, name => 'Item 2', description => 'Second item' },
        ];
    }

    1;
}

# Create test handlers
package TestAPI::Handlers::Items {
    use parent 'PAGI::OpenAPI::Handler';
    use Future::AsyncAwait;

    async sub list {
        my ($self, $c) = @_;
        my $items = $c->items;
        my $limit = $c->query('limit') // 10;

        my @result = @$items[0 .. ($limit - 1 < $#$items ? $limit - 1 : $#$items)];
        await $c->json({ items => \@result });
    }

    async sub get {
        my ($self, $c) = @_;
        my $id = $c->path_param('id');
        my $items = $c->items;

        my ($item) = grep { $_->{id} == $id } @$items;

        return await $c->not_found("Item not found") unless $item;
        await $c->json($item);
    }

    async sub create {
        my ($self, $c) = @_;
        my $data = await $c->request_json;
        my $items = $c->items;

        my $new_id = (@$items ? (sort { $b <=> $a } map { $_->{id} } @$items)[0] : 0) + 1;
        my $item = {
            id          => $new_id,
            name        => $data->{name},
            description => $data->{description},
        };

        push @$items, $item;
        await $c->status(201)->json($item);
    }

    async sub delete {
        my ($self, $c) = @_;
        my $id = $c->path_param('id');
        my $items = $c->items;

        my $before = @$items;
        @$items = grep { $_->{id} != $id } @$items;

        return await $c->not_found("Item not found") if @$items == $before;
        await $c->status(204)->send;
    }

    1;
}

# Set schema path
$TestAPI::SCHEMA_PATH = $schema_path;

# Create app with lifespan enabled
my $app = TestAPI->to_app;
my $client = PAGI::Test::Client->new(app => $app, lifespan => 1);
$client->start;

subtest 'GET /openapi.json' => sub {
    my $res = $client->get('/openapi.json');
    is $res->status, 200, 'status 200';
    is $res->header('content-type'), 'application/json; charset=utf-8', 'content type';

    my $schema = $res->json;
    is $schema->{openapi}, '3.1.0', 'openapi version';
    is $schema->{info}{title}, 'Test API', 'title';
    ok exists $schema->{paths}{'/items'}, 'has /items path';
};

subtest 'GET /openapi.yaml' => sub {
    my $res = $client->get('/openapi.yaml');
    is $res->status, 200, 'status 200';
    like $res->header('content-type'), qr{application/yaml}, 'content type';
    like $res->text, qr/openapi: ['"]?3\.1\.0/, 'yaml contains openapi version';
};

subtest 'GET /docs' => sub {
    my $res = $client->get('/docs');
    is $res->status, 200, 'status 200';
    like $res->header('content-type'), qr{text/html}, 'content type';
    like $res->text, qr/swagger-ui/, 'contains swagger-ui';
};

subtest 'GET /items - list' => sub {
    my $res = $client->get('/items');
    is $res->status, 200, 'status 200';

    my $data = $res->json;
    ok exists $data->{items}, 'has items key';
    is scalar(@{$data->{items}}), 2, 'has 2 items';
    is $data->{items}[0]{name}, 'Item 1', 'first item name';
};

subtest 'GET /items with limit' => sub {
    my $res = $client->get('/items?limit=1');
    is $res->status, 200, 'status 200';

    my $data = $res->json;
    is scalar(@{$data->{items}}), 1, 'limited to 1 item';
};

subtest 'GET /items/1 - get existing' => sub {
    my $res = $client->get('/items/1');
    is $res->status, 200, 'status 200';

    my $item = $res->json;
    is $item->{id}, 1, 'item id';
    is $item->{name}, 'Item 1', 'item name';
};

subtest 'GET /items/999 - not found' => sub {
    my $res = $client->get('/items/999');
    is $res->status, 404, 'status 404';

    my $data = $res->json;
    like $data->{error}, qr/not found/i, 'error message';
};

subtest 'POST /items - create' => sub {
    my $res = $client->post('/items', json => {
        name        => 'New Item',
        description => 'A new item',
    });
    is $res->status, 201, 'status 201';

    my $item = $res->json;
    ok $item->{id}, 'has id';
    is $item->{name}, 'New Item', 'name matches';

    # Verify it was added
    my $list_res = $client->get('/items');
    is scalar(@{$list_res->json->{items}}), 3, 'now has 3 items';
};

subtest 'DELETE /items/:id - delete' => sub {
    my $res = $client->delete('/items/1');
    is $res->status, 204, 'status 204';

    # Verify it was deleted
    my $get_res = $client->get('/items/1');
    is $get_res->status, 404, 'item no longer exists';
};

done_testing;
