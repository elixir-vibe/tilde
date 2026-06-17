# VibeKit quality gate

## Development

```sh
mix deps.get
mix ci
```

## Conventions

- Use `mix ci` for the full validation suite before finishing changes.
- For Phoenix/web apps, keep Phoenix's generated guidance, but treat this VibeKit section as the final quality gate.
- For non-web Elixir projects, VibeKit is the default project baseline.
- Keep changes small, tested, and formatted.

## QuackDB / storage conventions

- Do not use raw SQL strings or ad hoc SQL fragments for Tilde storage work.
- Use Ecto, Ecto migrations, and QuackDB's Ecto/query DSL and helper modules for schema, writes, reads, search, and analytics.
- Keep Tilde core storage-neutral; QuackDB belongs behind a storage adapter/repository boundary.
- Before designing or changing QuackDB-backed storage, read the QuackDB reference docs:
  - https://hexdocs.pm/quackdb/readme.html
  - https://hexdocs.pm/quackdb/getting-started.html
  - https://hexdocs.pm/quackdb/type-support.html
  - https://hexdocs.pm/quackdb/managed-duckdb.html
  - https://hexdocs.pm/quackdb/sources.html
  - https://hexdocs.pm/quackdb/full-text-search.html
  - https://hexdocs.pm/quackdb/telemetry.html
  - https://hexdocs.pm/quackdb/coverage.html
  - https://hexdocs.pm/quackdb/ecto-analytical-coverage.html
  - https://hexdocs.pm/quackdb/public-api-audit.html
