# Bookstore API Example

A comprehensive bookstore API demonstrating advanced PAGI::OpenAPI features.

## Features Demonstrated

- **Multiple handler classes** - Books, Authors, Reviews, Auth handlers
- **Bearer token authentication** - Custom auth helper with `$c->bearer_token`
- **Resource relationships** - Books have authors, books have reviews
- **Pagination** - Page/per_page query params with pagination metadata
- **Filtering** - By author_id, genre
- **Custom helpers** - `$c->db` for database, `$c->auth` for authentication
- **Protected routes** - Some endpoints require authentication
- **Complex responses** - Nested objects with related data

## Running

```bash
cd examples/bookstore-api
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

## Code Structure

```
app.pl
├── BookstoreAPI (main app)
│   ├── openapi_schema() → schema.yaml
│   ├── build_helpers() → { db, auth }
│   └── on_startup() → seed sample data
├── BookstoreAPI::Auth (token helper)
│   ├── create_token()
│   └── verify_token()
├── BookstoreAPI::DB (in-memory database)
│   ├── Book methods
│   ├── Author methods
│   └── Review methods
└── Handlers
    ├── BookstoreAPI::Handlers::Auth
    ├── BookstoreAPI::Handlers::Books
    ├── BookstoreAPI::Handlers::Authors
    └── BookstoreAPI::Handlers::Reviews
```

## Sample Data

The API starts with sample data:
- 3 authors (Tolkien, King, Asimov)
- 4 books (LOTR, The Hobbit, The Shining, Foundation)
- 5 reviews across the books
