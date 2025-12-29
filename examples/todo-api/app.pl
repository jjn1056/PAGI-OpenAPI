#!/usr/bin/env perl
# Todo API Example
#
# Run with: pagi-server -Ilib -I../../lib --app app.pl --port 5000
# Or directly: pagi-server -Ilib -I../../lib ./lib/TodoAPI.pm --port 5000
#
# Visit http://localhost:5000/docs for Swagger UI

use strict;
use warnings;
use lib 'lib';

use TodoAPI;

TodoAPI->to_app;
