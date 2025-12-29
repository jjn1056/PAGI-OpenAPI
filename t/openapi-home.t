use strict;
use warnings;
use Test2::V0;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);

BEGIN {
    eval { require OpenAPI::Modern; 1 }
        or plan skip_all => 'OpenAPI::Modern not installed';
}

use PAGI::OpenAPI;

# Create a test app class
package TestHomeAPI {
    use parent 'PAGI::OpenAPI';
    sub openapi_schema { undef }  # No schema for these tests
}

subtest 'home() returns Path::Tiny object' => sub {
    my $app = TestHomeAPI->new;
    my $home = $app->home;

    ok $home, 'home() returns a value';
    ok $home->isa('Path::Tiny'), 'home() returns Path::Tiny object';
    ok $home->is_absolute, 'home path is absolute';
};

subtest 'home() is cached' => sub {
    my $app = TestHomeAPI->new;
    my $home1 = $app->home;
    my $home2 = $app->home;

    is "$home1", "$home2", 'home() returns same path on subsequent calls';
};

subtest 'home_path() builds relative paths' => sub {
    my $app = TestHomeAPI->new;
    my $home = $app->home;

    my $schema_path = $app->home_path('schemas', 'openapi.yaml');
    ok $schema_path->isa('Path::Tiny'), 'home_path() returns Path::Tiny';

    my $expected = $home->child('schemas', 'openapi.yaml');
    is "$schema_path", "$expected", 'home_path() correctly builds path';
};

subtest 'PAGI_HOME environment variable override' => sub {
    my $temp = tempdir(CLEANUP => 1);

    local $ENV{PAGI_HOME} = $temp;

    # Create fresh app (clear cached home)
    my $app = TestHomeAPI->new;
    my $home = $app->home;

    is "$home", path($temp)->absolute->stringify, 'PAGI_HOME overrides detection';
};

subtest 'home detection strips lib directory' => sub {
    # This tests the auto-detection from %INC
    # TestHomeAPI is already in %INC from the package declaration

    my $app = TestHomeAPI->new;
    my $home = $app->home;

    # The home should not end with /lib
    ok $home->basename ne 'lib', 'home does not end with lib/';
};

subtest 'home_path with single component' => sub {
    my $app = TestHomeAPI->new;

    my $config = $app->home_path('config.yaml');
    my $expected = $app->home->child('config.yaml');

    is "$config", "$expected", 'single component works';
};

done_testing;
