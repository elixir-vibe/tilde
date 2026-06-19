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

## UI/style conventions

- Do not introduce ad hoc component or CSS class names when an existing semantic class/component fits.
- Before adding UI classes/components, read nearby component modules and CSS files and reuse the established vocabulary.
- CSS class names use the existing semantic style (`actions`, `action`, `tool`, `choice`, etc.); do not invent dashed or underscored variants as quick fixes.
- Shared affordances such as shortcut/action controls should go through shared LiveView components and shared CSS, not one-off markup per block.

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
