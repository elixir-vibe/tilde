# Tilde

Tilde is a semantic agent console for Elixir.

One event-driven session model powers LiveView, terminal, and SSH interfaces. The
session—not DOM, ANSI output, terminal cells, or transport state—is the source of
truth. Tilde adds supervised session ownership, Jidoka-backed agent execution,
renderer-neutral workspace orchestration, and optional QuackDB persistence.

## Why Tilde?

- **One semantic model** — events reduce into transcript blocks, widgets, input,
  assistant lifecycle, and session metadata.
- **Multiple renderers** — the same state renders as LiveView DOM, terminal ANSI,
  SSH output, plain text, or JSON-compatible data.
- **Transport-neutral interactions** — browser events and terminal keys become
  `Tilde.Core.Interaction` values before application behavior runs.
- **Supervised concurrency** — named sessions and agent tasks live under OTP
  supervisors with explicit crash, timeout, and cleanup behavior.
- **Durable resume** — QuackDB stores sequenced events, searchable projections,
  and resumable draft state through Ecto.
- **Shared workbench behavior** — LiveView and SSH reuse workspace, review,
  palette, scrolling, and shortcut orchestration through `Tilde.Workbench`.

```text
raw input
  ↓
Tilde.Core.Interaction
  ↓
Tilde.Index / Tilde.Session.Controller / Tilde.Workbench
  ↓
Tilde.Core.Session + Tilde.Core.Event
  ↓
semantic transcript and widgets
  ↓
LiveView / TUI / SSH / text / JSON
```

See [`docs/architecture.md`](docs/architecture.md) for the complete boundary and
lifecycle design.

## Run the mirrored demo

The standalone demo serves the same named sessions over LiveView and SSH.

```sh
mix deps.get
mix assets.build
mix tilde.demo
```

Open:

- LiveView index: <http://localhost:4000/>
- Component playground: <http://localhost:4000/playground>
- Named session: `http://localhost:4000/sessions/<session_id>`

Connect over SSH:

```sh
ssh tilde@localhost -p 4022 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null
```

The task prints a generated password. Override it with `--password` or
`TILDE_DEMO_PASSWORD`.

Useful options:

```sh
mix tilde.demo \
  --web-port 4100 \
  --ssh-port 4122 \
  --password "use-a-long-random-password"
```

SSH starts on the session index. Open a session from the list or use
`/attach <session_id>`; the matching browser route and every attached SSH client
then observe the same submitted transcript. Each SSH client keeps its prompt
buffer local until submission.

## Core model

Events are the durable history. A session assigns every appended event a
monotonic sequence and incrementally derives the transcript and assistant state.

```elixir
alias Tilde.Core.Session

session =
  Tilde.session(id: "demo")
  |> Session.append_event(Tilde.user_message("Run the tests"))
  |> Session.append_event(Tilde.assistant_done("All tests passed."))

Tilde.Renderer.Text.render(session.transcript)
Session.events(session)
```

The in-memory log is optimized for constant-time append. Use
`Session.events/1` for chronological replay rather than reading its internal log
field.

Tools use the same event stream:

```elixir
session =
  Tilde.session()
  |> Session.append_event(
    Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
  )
  |> Session.append_event(Tilde.tool_stream("tool_1", :stdout, "Compiling…\n"))
  |> Session.append_event(Tilde.tool_done("tool_1", :success, %{exit_code: 0}))
```

Renderers derive compact/expanded tool views, stream identity, controls, and
metadata from that semantic state.

## Supervised sessions

Start named sessions through the session supervisor. Registry tuples support
user-provided ids without creating atoms.

```elixir
alias Tilde.Session.{Registry, Server}

name = Registry.via("demo")

{:ok, _pid} =
  Server.ensure_started(name,
    session: Tilde.session(id: "demo")
  )

session = Server.subscribe(name)
updated = Server.append_event(name, Tilde.input_submitted("hello"))
```

`Tilde.Application` owns the registry, dynamic session supervisor, and agent task
supervisor. Session children are temporary: after a crash, the next connection
opens the last durable state instead of restarting stale memory.

## Rendering

### Plain text and JSON-compatible data

```elixir
text = Tilde.Renderer.Text.render(session.transcript)
data = Tilde.Renderer.JSON.render(session)
```

### TUI

```elixir
ansi = Tilde.Renderer.TUI.render_to_string(session, width: 80, height: 30)
```

The TUI uses `Inspect.Algebra` for width-aware layout and `IO.ANSI` only at the
renderer boundary.

### LiveView

```elixir
import Tilde.Transport.Live.Console

~H"""
<.console session={@session} />
"""
```

The Live components emit ordinary events such as `tilde:toggle_expand`; the
parent LiveView translates them through `Tilde.Transport.Live.Interaction` and
applies resulting outcomes. Build the Volt-managed assets and include
`/assets/css/app.css` and `/assets/js/app.js` in the host layout.

### SSH

`Tilde.Transport.SSH.Demo` runs an Erlang/OTP SSH daemon backed by
`Tilde.Transport.SSH.Channel`. SSH is a transport for the semantic TUI, not an OS
shell or terminal emulator. Host keys are generated with `:public_key` under
`_build/tilde_ssh/system`; Tilde does not invoke `ssh-keygen`.

## Semantic HEEx templates

Tilde compiles a constrained semantic HEEx surface directly into widgets or view
cells. It does not render HTML and parse it back.

```elixir
require Tilde.Template
require Tilde.Template.Renderer.Live
require Tilde.Template.Renderer.TUI

source = """
<.tool state="success">
  <.tool_call name="bash" segment="mix test" />
  <.line role="metadata"><.meta>cwd /tmp/app  exit 0</.meta></.line>
  <.line role="primary"><.primary>ok</.primary></.line>
</.tool>
"""

cells = Tilde.Template.to_cells!(source)
ansi = Tilde.Template.Renderer.TUI.render!(source, 80)
live = Tilde.Template.Renderer.Live.render!(source)
```

Widget templates use components such as `<.screen>`, `<.section>`,
`<.widget_text>`, `<.widget_suggest>`, `<.widget_input>`, `<.shortcut_bar>`, and
`<.widget_footer>`. Cell templates provide messages, Markdown, tools, choices,
lines, and semantic inline roles.

## Agent runtime

Tilde delegates agent execution to Jidoka and keeps the resulting console state
in Tilde events. `Tilde.Runtime.JidokaEvent` projects runtime deltas, tool
lifecycles, terminal results, and failures; `Tilde.Runtime.Metadata` rejects
runtime-only values before metadata reaches durable events.

The demo enables assistant replies automatically. Configure OpenRouter with:

```sh
export OPENROUTER_API_KEY="..."
```

```elixir
config :tilde,
  llm_enabled: true,
  llm_model: "openrouter:~anthropic/claude-haiku-latest"
```

Without a key, the submitted user message remains in the semantic transcript and
the demo displays a configuration error instead of losing the session.

## Persistence

Storage is opt-in. Configure the QuackDB adapter and repository:

```elixir
config :tilde,
  storage_adapter: Tilde.Storage.QuackDB

config :tilde, Tilde.Storage.Repo,
  uri: System.fetch_env!("TILDE_QUACKDB_URI"),
  token: System.get_env("TILDE_QUACKDB_TOKEN")
```

Run the Ecto migrations:

```elixir
{:ok, _versions} = Tilde.Storage.Setup.migrate()
```

QuackDB stores:

- canonical sequenced session events
- searchable text projections
- resumable input and metadata state
- session summaries for index discovery

The event codec is a versioned JSON-compatible schema. Storage failures are
explicit: `Tilde.Session.Persistence` raises `Tilde.Storage.Error` rather than
allowing a session server to acknowledge state that was not stored.

## Commands and controls

The command layer is renderer-neutral. Built-in commands include:

```text
/help               list commands
/session            show session details
/attach <name>      attach to a named session
/detach             return to the index
/new [name]         create or open an isolated session
/clear              clear the current session
/compact [guidance] summarize older context
/quit               close an SSH/TUI session
```

Common terminal controls:

```text
ctrl+p       open the palette
ctrl+o       expand or collapse the focused tool
arrow keys   navigate suggestions and workbench surfaces
enter        accept or submit
esc          cancel the current local surface
ctrl+c       interrupt active work or clear local input
```

## Module map

| Area | Main modules |
| --- | --- |
| Semantic state | `Tilde.Core.Event`, `Tilde.Core.Session`, `Tilde.Core.Transcript`, `Tilde.Core.Widget` |
| Application behavior | `Tilde.Index`, `Tilde.Session.Controller`, `Tilde.Session.Suggestions`, `Tilde.Workbench` |
| Process ownership | `Tilde.Session.Server`, `Tilde.Session.Registry`, `Tilde.Session.Supervisor` |
| Rendering | `Tilde.Renderer.Text`, `Tilde.Renderer.JSON`, `Tilde.Renderer.TUI`, `Tilde.Transport.Live.Console` |
| Runtime | `Tilde.Runtime.LLM`, `Tilde.Runtime.JidokaEvent`, `Tilde.Runtime.Metadata` |
| Storage | `Tilde.Storage`, `Tilde.Storage.QuackDB`, `Tilde.Storage.Setup` |
| Templates | `Tilde.Template`, `Tilde.Template.Renderer.Live`, `Tilde.Template.Renderer.TUI` |
| Demo transports | `Tilde.Demo.Live`, `Tilde.Transport.SSH.Demo`, `Tilde.Transport.SSH.Channel` |

## Development

Run the complete quality gate:

```sh
mix deps.get
mix ci
```

Run the managed QuackDB integration test explicitly:

```sh
TILDE_QUACKDB_INTEGRATION=1 \
QUACKDB_TEST_DUCKDB=managed \
mix test test/tilde/storage/quackdb_integration_test.exs
```

Additional design notes:

- [`docs/architecture.md`](docs/architecture.md) — boundaries, supervision,
  persistence, interactions, workbench, and runtime lifecycle
- [`docs/ui.md`](docs/ui.md) — semantic UI and styling conventions
- [`docs/jidoka-upstream-gaps.md`](docs/jidoka-upstream-gaps.md) — runtime
  semantics that belong upstream
