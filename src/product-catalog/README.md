# Product Catalog Service

When this service is run the output should be similar to the following

```json
{"message":"successfully parsed product catalog json","severity":"info","timestamp":"2022-06-02T23:54:10.191283363Z"}
{"message":"starting grpc server at :3550","severity":"info","timestamp":"2022-06-02T23:54:10.191849078Z"}
```

## Local Build

To build the service binary, run:

```sh
go build -o /go/bin/product-catalog/
```

## Docker Build

From the root directory, run:

```sh
docker compose build product-catalog
```

Database Calls Instrumentation

PostgreSQL queries are instrumented with
[otelsql](https://pkg.go.dev/github.com/XSAM/otelsql), with SQLCommenter enabled
to append trace context to SQL statements (for example, `traceparent` key-value
pairs in query comments).

The option is configured in `main.go` when opening the database connection:

```go
db, err = otelsql.Open("postgres", connStr,
    dbAttrs,
    otelsql.WithSQLCommenter(true),
    otelsql.WithSpanOptions(...),
)
```

Queries must use context-aware methods such as `QueryContext` and
`QueryRowContext` so the active trace context is available when SQL comments
are injected.

## Regenerate protos

To build the protos, run from the root directory:

```sh
make docker-generate-protobuf
```

## Generate feature flag types

To regenerate the typed feature flag accessors from `flags.json`, run from the
service directory:

```sh
go generate ./...
```

This uses the [OpenFeature CLI](https://github.com/open-feature/cli) to
produce `flags/flags_gen.go`.

## Noisy telemetry scenario

The `productCatalogNoisyTelemetry` feature flag makes `GetProduct` emit extra
`product.lookup` spans and "Product lookup" log records on every request. Use
it to overload the OpenTelemetry Collector.

The flag is an integer and defaults to 0 (`off`). The variants `x100`, `x1000`,
`x2000`, `x3000` and `x10000` set how many extra spans and log records each
request emits. Change the variant in the feature flag UI.

Total volume is the multiplier times the `GetProduct` request rate, so the
load-generator user count (`LOCUST_USERS`) scales it too. High multipliers slow
the service and can starve the rest of the demo of resources.

## Bump dependencies

To bump all dependencies run:

```sh
go get -u -t ./...
go mod tidy
```
