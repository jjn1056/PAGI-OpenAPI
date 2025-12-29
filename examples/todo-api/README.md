# Todo API Example

A simple CRUD todo list API demonstrating PAGI::OpenAPI basics.

## Features Demonstrated

- **Basic CRUD operations** - Create, Read, Update, Delete todos
- **Query parameters** - Filtering by `completed` status, `limit` results
- **Path parameters** - `/todos/{id}` for specific todo access
- **Request body parsing** - `await $c->request_json`
- **Error shortcuts** - `$c->not_found()`, `$c->bad_request()`
- **Response chaining** - `$c->status(201)->json($data)`
- **In-memory storage** - Simple Store class for data
- **Helper access** - `$c->todos` for store access

## Running

```bash
cd examples/todo-api
pagi-server --app app.pl --port 5000
```

Visit http://localhost:5000/docs for Swagger UI.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /todos | List all todos |
| POST | /todos | Create a new todo |
| GET | /todos/{id} | Get a specific todo |
| PUT | /todos/{id} | Update a todo |
| DELETE | /todos/{id} | Delete a todo |
| POST | /todos/{id}/complete | Mark todo as complete |

## Example Requests

```bash
# List all todos
curl http://localhost:5000/todos

# Create a todo
curl -X POST http://localhost:5000/todos \
  -H "Content-Type: application/json" \
  -d '{"title": "Learn PAGI", "description": "Build an API"}'

# Get a specific todo
curl http://localhost:5000/todos/1

# Filter by completed status
curl "http://localhost:5000/todos?completed=false"

# Mark as complete
curl -X POST http://localhost:5000/todos/1/complete

# Delete a todo
curl -X DELETE http://localhost:5000/todos/1
```

## Code Structure

```
app.pl
├── TodoAPI (main app)
│   ├── openapi_schema() → schema.yaml
│   ├── build_helpers() → { todos => $store }
│   └── on_startup() → initialize store
├── TodoAPI::Store (in-memory storage)
└── TodoAPI::Handlers::Todos
    ├── list() - GET /todos
    ├── get() - GET /todos/{id}
    ├── create() - POST /todos
    ├── update() - PUT /todos/{id}
    ├── delete() - DELETE /todos/{id}
    └── complete() - POST /todos/{id}/complete
```
