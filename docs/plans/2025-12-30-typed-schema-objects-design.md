# Typed Schema Objects Design

## Overview

Auto-generate typed request/response objects from OpenAPI schema definitions. Instead of working with raw hashrefs, handlers receive and return structured objects with accessors, validation, and introspection.

## Goals

- Cleaner handler code with typed accessors
- Automatic validation with meaningful field-level errors
- Introspection support for debugging and tooling
- Backwards compatible (existing `request_json`/`json` still work)

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Generation timing | In-memory at startup | Always in sync with schema, no drift |
| Request method | `await $c->request_object` | Explicit, backwards compatible |
| Response method | `await $c->respond($data)` | Schema-aware, content-type aware |
| Content types | JSON + text/plain | YAGNI, covers 99% of cases |
| Object mutability | Immutable (getters only) | Safer, simpler |
| Nested objects | Eager construction | Truly immutable, simpler code |
| Namespaces | Request/Response/Schema | Clear separation by usage |
| Classification | Scan actual usage | Automatic, no conventions needed |
| Validation errors | Auto-respond 400 | Matches existing behavior |
| Introspection | `->fields` API | Simple, avoids `->meta` collision |

## Architecture

### New Module

`PAGI::OpenAPI::SchemaObjects` - Generates classes at startup:

1. Parses `components/schemas` from OpenAPI spec
2. Scans operations to classify schemas (request/response/shared)
3. Generates Perl classes in-memory
4. Stores in `$app->state->{_schema_classes}`

### Generated Namespaces

```
TodoAPI::Request::TodoInput    # requestBody-only schemas
TodoAPI::Response::Todo        # response-only schemas
TodoAPI::Response::Error
TodoAPI::Schema::User          # used in both request and response
```

### Configuration Methods

```perl
sub request_namespace  { 'MyApp::Request' }   # default: AppName::Request
sub response_namespace { 'MyApp::Response' }  # default: AppName::Response
sub shared_namespace   { 'MyApp::Schema' }    # default: AppName::Schema
```

## Generated Class Structure

```perl
package TodoAPI::Request::TodoInput;
use strict;
use warnings;

my %FIELDS;
my @FIELD_NAMES;
my @REQUIRED;

sub new {
    my ($class, %args) = @_;
    return bless {
        title       => $args{title},
        description => $args{description},
        completed   => $args{completed},
    }, $class;
}

# Getters
sub title       { shift->{title} }
sub description { shift->{description} }
sub completed   { shift->{completed} }

# Introspection
sub fields          { \%FIELDS }
sub field_names     { \@FIELD_NAMES }
sub required_fields { \@REQUIRED }
sub schema_name     { 'TodoInput' }
sub namespace_type  { 'request' }

# Serialization
sub TO_JSON { return { %{shift()} } }

1;
```

### Nested Objects (Eager Construction)

```perl
sub new {
    my ($class, %args) = @_;
    return bless {
        id    => $args{id},
        order => TodoAPI::Response::Order->new(%{$args{order} // {}}),
        items => [ map { TodoAPI::Response::Item->new(%$_) } @{$args{items} // []} ],
    }, $class;
}
```

## FieldInfo Class

```perl
package PAGI::OpenAPI::FieldInfo;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

sub name       { shift->{name} }
sub type       { shift->{type} }        # string|integer|boolean|array|object
sub required   { shift->{required} // 0 }
sub class      { shift->{class} }       # for type: object
sub item_class { shift->{item_class} }  # for type: array of objects
sub item_type  { shift->{item_type} }   # for type: array of scalars

1;
```

## Context Methods

### request_object

```perl
async sub request_object {
    my ($self) = @_;

    my $class = $self->_request_body_class
        or croak "No requestBody schema defined for this operation";

    my $data = await $self->request_json;
    my $errors = $self->_collect_validation_errors($data, $class);

    if (@$errors) {
        await $self->status(400)->json({
            error   => 'Validation failed',
            details => $errors,
        });
        return undef;
    }

    return $class->new(%$data);
}
```

### respond

```perl
async sub respond {
    my ($self, $data, $status) = @_;
    $status //= $self->{_response_status} // 200;

    my $content_type = $self->_response_content_type($status);

    if ($content_type =~ m{application/json}) {
        my $class = $self->_response_body_class($status);
        my $obj = $class ? $class->new(%$data) : $data;
        await $self->json($obj);
    }
    elsif ($content_type =~ m{text/plain}) {
        await $self->text($data);
    }
    else {
        croak "Unsupported response content-type: $content_type";
    }
}
```

## Error Response Format

```json
{
  "error": "Validation failed",
  "details": [
    {"path": "/title", "message": "is required"},
    {"path": "/completed", "message": "expected boolean, got string"}
  ]
}
```

## Handler Usage

```perl
async sub create {
    my ($self, $c) = @_;

    my $input = await $c->request_object or return;
    # $input->title, $input->description, $input->completed

    my $todo = $c->todos->create($input);
    await $c->respond($todo);
}
```

---

# Implementation Plan

Each step: run all tests at start, implement, write tests, run all tests at end. Fix regressions before proceeding.

## Step 1: FieldInfo Class

**Goal:** Create the field metadata class.

**Tasks:**
1. Run existing tests to establish baseline
2. Create `lib/PAGI/OpenAPI/FieldInfo.pm`
3. Implement: `new`, `name`, `type`, `required`, `class`, `item_class`, `item_type`
4. Write `t/openapi-fieldinfo.t` testing all accessors
5. Add POD documentation
6. Run all tests

**Files:**
- `lib/PAGI/OpenAPI/FieldInfo.pm` (new)
- `t/openapi-fieldinfo.t` (new)

## Step 2: Schema Classification

**Goal:** Classify schemas as request/response/shared by scanning operations.

**Tasks:**
1. Run all tests
2. Add `_classify_schemas` method to `PAGI::OpenAPI::SchemaObjects`
3. Create `lib/PAGI/OpenAPI/SchemaObjects.pm` with classification logic
4. Write `t/openapi-schema-classify.t` testing classification
5. Test with todo-api schema (TodoInput=request, Todo=response, Error=response)
6. Run all tests

**Files:**
- `lib/PAGI/OpenAPI/SchemaObjects.pm` (new)
- `t/openapi-schema-classify.t` (new)

## Step 3: Code Generation for Simple Schemas

**Goal:** Generate classes for schemas with scalar properties only.

**Tasks:**
1. Run all tests
2. Add `_generate_class` method to SchemaObjects
3. Generate: package, new(), getters, TO_JSON
4. Generate: fields(), field_names(), required_fields(), schema_name(), namespace_type()
5. Populate %FIELDS with FieldInfo objects
6. Write `t/openapi-schema-generate.t` testing generated classes
7. Test introspection methods
8. Run all tests

**Files:**
- `lib/PAGI/OpenAPI/SchemaObjects.pm` (modify)
- `t/openapi-schema-generate.t` (new)

## Step 4: Nested Object Support

**Goal:** Handle schemas with nested objects and arrays.

**Tasks:**
1. Run all tests
2. Extend `_generate_class` to handle `type: object` with `$ref`
3. Extend to handle `type: array` with `items.$ref`
4. Implement eager construction in generated `new()`
5. Set `class`, `item_class`, `item_type` in FieldInfo
6. Write `t/openapi-schema-nested.t` with complex schema
7. Run all tests

**Files:**
- `lib/PAGI/OpenAPI/SchemaObjects.pm` (modify)
- `t/openapi-schema-nested.t` (new)

## Step 5: Integration with PAGI::OpenAPI

**Goal:** Generate classes at app startup.

**Tasks:**
1. Run all tests
2. Add namespace configuration methods to PAGI::OpenAPI
3. Call SchemaObjects from `_load_schema`
4. Store generated classes in `$self->state->{_schema_classes}`
5. Write `t/openapi-schema-integration.t` verifying classes exist after app init
6. Run all tests

**Files:**
- `lib/PAGI/OpenAPI.pm` (modify)
- `lib/PAGI/OpenAPI/SchemaObjects.pm` (modify)
- `t/openapi-schema-integration.t` (new)

## Step 6: request_object Method

**Goal:** Add typed request body parsing to Context.

**Tasks:**
1. Run all tests
2. Add `_request_body_class` helper to Context
3. Implement `request_object` method
4. Implement `_collect_validation_errors` for field-level errors
5. Write `t/openapi-request-object.t` testing:
   - Valid input returns typed object
   - Invalid input returns 400 with field errors
   - Missing requestBody schema croaks
6. Run all tests

**Files:**
- `lib/PAGI/OpenAPI/Context.pm` (modify)
- `t/openapi-request-object.t` (new)

## Step 7: respond Method

**Goal:** Add schema-aware response method to Context.

**Tasks:**
1. Run all tests
2. Add `_response_content_type` and `_response_body_class` helpers
3. Implement `respond` method (JSON + text/plain)
4. Write `t/openapi-respond.t` testing:
   - JSON response wraps in typed object
   - text/plain response sends as text
   - Unsupported content-type croaks
5. Run all tests

**Files:**
- `lib/PAGI/OpenAPI/Context.pm` (modify)
- `t/openapi-respond.t` (new)

## Step 8: Update todo-api Example

**Goal:** Demonstrate typed objects in example app.

**Tasks:**
1. Run all tests
2. Update TodoAPI::Handlers::Todos to use `request_object` and `respond`
3. Verify example still works manually
4. Update/add integration test for todo-api
5. Run all tests

**Files:**
- `examples/todo-api/lib/TodoAPI/Handlers/Todos.pm` (modify)
- `t/openapi-basic.t` (modify if needed)

## Step 9: Documentation

**Goal:** Complete POD documentation for all new features.

**Tasks:**
1. Run all tests
2. Document SchemaObjects in PAGI::OpenAPI POD
3. Document `request_object` and `respond` in Context POD
4. Document FieldInfo class
5. Document namespace configuration methods
6. Add SYNOPSIS examples
7. Run `podchecker` on all modified files
8. Run all tests

**Files:**
- `lib/PAGI/OpenAPI.pm` (POD)
- `lib/PAGI/OpenAPI/Context.pm` (POD)
- `lib/PAGI/OpenAPI/SchemaObjects.pm` (POD)
- `lib/PAGI/OpenAPI/FieldInfo.pm` (POD)

## Step 10: Final Code Survey

**Goal:** Ensure quality and completeness.

**Tasks:**
1. Run all tests
2. Review each new/modified file for:
   - Untested code paths
   - Missing documentation
   - Dead code
   - Inconsistent naming
3. Verify docs match implementation
4. Check test coverage for edge cases:
   - Empty schemas
   - Optional fields
   - Deeply nested objects
   - Arrays of scalars vs objects
5. Run all tests
6. Run `podchecker` on all files
7. Manual smoke test with todo-api

**Checklist:**
- [ ] All public methods documented
- [ ] All public methods tested
- [ ] No dead code
- [ ] Docs match implementation
- [ ] Example app updated
- [ ] All tests pass

---

## Future Enhancements (Not in Scope)

- File generation for IDE support (`pagi-openapi dump-types`)
- Full constraint introspection (min_length, pattern, enum, etc.)
- XML/other content-type support
- Custom validators per field
