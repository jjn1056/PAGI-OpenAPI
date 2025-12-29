# Bookstore API Example

A comprehensive bookstore API demonstrating advanced PAGI::OpenAPI features
with a proper lib/ directory structure.

## Features Demonstrated

- **Proper lib/ structure** - Separate module files for clean organization
- **Multiple handler classes** - Books, Authors, Reviews, Auth handlers
- **Bearer token authentication** - Custom auth service with `$c->bearer_token`
- **Resource relationships** - Books have authors, books have reviews
- **Pagination** - Page/per_page query params with pagination metadata
- **Filtering** - By author_id, genre
- **Custom services** - `$c->db` for database, `$c->auth` for authentication
- **Protected routes** - Some endpoints require authentication
- **home() auto-detection** - Schema and static files resolved relative to app home
- **run_if_script** - Module is directly runnable without app.pl wrapper

## Running

```bash
cd examples/bookstore-api

# Run the module directly via pagi-server
pagi-server -Ilib -I../../lib ./lib/BookstoreAPI.pm --port 5000

# Or use the app.pl wrapper
pagi-server --app app.pl --port 5000
```

Visit http://localhost:5000/docs for Swagger UI.

## Authentication

Most write operations require a bearer token:

```bash
# Get a token (accepts any username/password for demo)
curl -X POST http://localhost:5000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username": "demo", "password": "demo"}'

# Response:
# {"token": "demo:1234567890:abc123...", "user": "demo"}

# Use the token
curl http://localhost:5000/books \
  -H "Authorization: Bearer demo:1234567890:abc123..."
```

## API Endpoints

### Books
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /books | No | List books (paginated, filterable) |
| POST | /books | Yes | Add a new book |
| GET | /books/{id} | No | Get book with author and reviews |
| PUT | /books/{id} | Yes | Update a book |
| DELETE | /books/{id} | Yes | Delete a book |

### Authors
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /authors | No | List all authors with book counts |
| POST | /authors | Yes | Add a new author |
| GET | /authors/{id} | No | Get author with their books |

### Reviews
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /books/{id}/reviews | No | Get reviews for a book |
| POST | /books/{id}/reviews | Yes | Add a review |

### Auth
| Method | Path | Description |
|--------|------|-------------|
| POST | /auth/token | Get authentication token |

## Example Requests

```bash
# List books with pagination
curl "http://localhost:5000/books?page=1&per_page=5"

# Filter by genre
curl "http://localhost:5000/books?genre=sci-fi"

# Get book with full details
curl http://localhost:5000/books/1

# Get author with their books
curl http://localhost:5000/authors/1

# Add a review (requires auth)
TOKEN=$(curl -s -X POST http://localhost:5000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"reviewer","password":"x"}' | jq -r .token)

curl -X POST http://localhost:5000/books/1/reviews \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"rating": 5, "text": "Absolutely fantastic book!"}'
```

## Directory Structure

```
bookstore-api/
├── app.pl                              # Entry point
├── schema.yaml                         # OpenAPI schema
├── public/
│   └── index.html                      # Web frontend
└── lib/
    └── BookstoreAPI.pm                 # Main app class
    └── BookstoreAPI/
        ├── Auth.pm                     # Auth service
        ├── DB.pm                       # In-memory database
        └── Handlers/
            ├── Auth.pm                 # POST /auth/token
            ├── Authors.pm              # /authors endpoints
            ├── Books.pm                # /books endpoints
            └── Reviews.pm              # /books/{id}/reviews endpoints
```

## Key Concepts

### Home Directory Auto-Detection

The app automatically detects its home directory from the class location:

```perl
# In BookstoreAPI.pm
sub openapi_schema { 'schema.yaml' }  # Relative to home

# In setup_routes
my $html = $app->home_path('public', 'index.html');
```

### Service Pattern

Services use return-type-determines-scope:

```perl
sub setup_services {
    my ($self) = @_;

    # App-scoped: returns object directly
    $self->service(db => sub {
        my ($app) = @_;
        return BookstoreAPI::DB->new;
    });
}
```

## Sample Data

The API starts with sample data:
- 8 authors (Tolkien, King, Asimov, Christie, Orwell, Austen, Dickens, Hemingway)
- 24 books across various genres
- 5 reviews
