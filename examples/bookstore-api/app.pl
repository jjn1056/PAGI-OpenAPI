#!/usr/bin/env perl
# Bookstore API Example
#
# A comprehensive example demonstrating:
# - Proper lib/ directory structure
# - Service pattern with return-type-determines-scope
# - Multiple handler classes (Books, Authors, Reviews, Auth)
# - Bearer token authentication
# - home() for automatic app directory detection
#
# Run with: pagi-server --app app.pl --port 5000
# Then visit: http://localhost:5000/docs
#
# Get a token:
#   curl -X POST http://localhost:5000/auth/token \
#     -H "Content-Type: application/json" \
#     -d '{"username":"demo","password":"demo"}'
#
# Use it:
#   curl http://localhost:5000/books \
#     -H "Authorization: Bearer <token>"

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";

use BookstoreAPI;

BookstoreAPI->to_app;
