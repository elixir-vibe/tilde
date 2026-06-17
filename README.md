# Tilde

Tilde is a semantic agent console core.

It models a pi-like console without making ANSI, VT100 state, DOM nodes, or a
character grid the source of truth. The durable layer is an append-only event
log; transcripts, compact tool widgets, Markdown/inline views, LiveView
components, plain text exports, JSON snapshots, and future TUI adapters are all
derived from semantic data.

## Core shape

```text
Event log
  ↓
Semantic transcript
  ↓
Derived views
  ↓
Renderer adapters
```

Initial modules:

- `Tilde.Core.Event` — append-only console events
- `Tilde.Core.Transcript` — reducer from events to blocks
- `Tilde.Core.Block` — semantic transcript block
- `Tilde.Core.Stream` — lossless tool output streams
- `Tilde.Core.Display` — compact/expanded display state, including `ctrl+o`
- `Tilde.Core.Action` — semantic actions for renderers
- `Tilde.Core.Run` — inline text marks such as bold and underline
- `Tilde.Tool.ViewModel` — compact/expanded derived tool widget data with stream identity and metadata rows
- `Tilde.Renderer.Text` — plain text renderer
- `Tilde.Renderer.JSON` — JSON-compatible map renderer
- `Tilde.Core.Session` — event log, transcript, widgets, statuses, and metadata
- `Tilde.Core.Widget` — non-transcript UI regions such as above/below input and footer
- `Tilde.Core.Choice` — semantic choice/approval state
- `Tilde.Transport.Live.*` — LiveView components in the same package
- `Tilde.Runtime.Markdown` — behaviour-backed Markdown rendering facade
- `Tilde.Runtime.Markdown.Provider` / `Tilde.Runtime.Markdown.Provider.MDEx` — Markdown backend behaviour and MDEx implementation
- `Tilde.Transport.Live.Markdown` — LiveView Markdown renderer with plain-text fallback
- `Tilde.Transport.Live.Run` — semantic inline rendering for bold, underline, code, links, and tones
- `Tilde.Renderer.TUI.*` — Inspect.Algebra + `IO.ANSI` terminal renderer building blocks
- `Tilde.Transport.SSH.*` — Erlang/OTP SSH demo server using generated `:public_key` host keys
- `Tilde.Transport.SSH.KeyProvider` / `Tilde.Transport.SSH.KeyProvider.PublicKey` — SSH host key provider behaviour and default implementation

## Example

```elixir
events = [
  Tilde.user_message("Run tests"),
  Tilde.assistant_delta("I'll run them."),
  Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1"),
  Tilde.tool_stream("tool_1", :stdout, "Compiling...\n"),
  Tilde.tool_stream("tool_1", :stdout, "2 tests, 0 failures\n"),
  Tilde.tool_done("tool_1", :success, %{exit_code: 0})
]

transcript = Tilde.transcript(events)
Tilde.Renderer.Text.render(transcript)
```

## Semantic HEEx templates

Tilde can parse a constrained, Tilde-native HEEx surface into semantic widgets
or low-level view cells:

```elixir
require Tilde.Template
require Tilde.Template.Renderer.TUI
require Tilde.Template.Renderer.Live

source = """
<.tool state="success">
  <.tool_call name="bash" segment="mix test" />
  <.line role="metadata"><.meta>cwd /tmp/app  exit 0</.meta></.line>
  <.line role="primary"><.primary>ok</.primary></.line>
</.tool>
"""

cells = Tilde.Template.to_cells!(source)
widgets = Tilde.Template.to_widgets!("""
<.screen id="home">
  <.widget_text kind="heading">tilde</.widget_text>
</.screen>
""")
ansi = Tilde.Template.Renderer.TUI.render!(source, 80)
live = Tilde.Template.Renderer.Live.render!(source)
```

The pipeline is source-semantic, not rendered-HTML based:

```text
HEEx source
  ↓ Phoenix.LiveView.TagEngine.Parser.parse!/2
HEEx AST
  ↓ Tilde.Template.Compiler
Tilde.Core.Widget or Tilde.View.Cell / Line / Text
  ↓
LiveView / TUI / SSH renderers
```

Tilde does **not** parse rendered HTML and does not use terminal emulation. The
supported template surface is intentionally Tilde-native. Widget templates use
components such as `<.screen>`, `<.section>`, `<.widget_text>`, `<.widget_suggest>`,
`<.widget_input>`, `<.shortcut_bar>`, and `<.widget_footer>`. Cell templates use
`<.cell>`, `<.message>`, `<.markdown>`, `<.tool>`, `<.choice>`, `<.suggest>`,
`<.line>`, `<.tool_call>`, and inline roles such as `<.title>`, `<.accent>`,
`<.meta>`, `<.primary>`, `<.muted>`, `<.error>`, `<.success>`, and `<.code>`. Basic source tags such as
`<ul>/<li>`, `<pre>`, and `<table>/<tr>/<th>/<td>` are mapped directly from the
HEEx source AST into text lines.

Arbitrary Phoenix function components are not a template compatibility target.
If a component should render to web, TUI, and SSH, model it as Tilde semantic
view data rather than HTML.

## LiveView

Tilde includes a LiveView renderer namespace in the same package:

```elixir
import Tilde.Transport.Live.Console

~H"""
<.console session={@session} />
"""
```

For default styling and hooks, build the Volt-managed TypeScript/CSS assets in
`assets/css/` and `assets/js/` and include the generated stylesheet/script from your layout.
The demo layout uses `Volt.static_path/2` for `/assets/css/app.css` and
`/assets/js/app.js`.

The Live components render semantic DOM for transcript blocks, tool widgets,
choice blocks, widgets, input, and footer/statusline content. Markdown message
source is rendered through the configured `Tilde.Runtime.Markdown.Provider`; the default
`Tilde.Runtime.Markdown.Provider.MDEx` backend uses MDEx's safe policy that omits raw HTML.
Components emit ordinary LiveView events such as `tilde:toggle_expand`; parent
LiveViews decide how to apply those events to session/transcript state.

A self-contained dogfood demo LiveView is included:

```elixir
# router.ex
live "/tilde", Tilde.Demo.Live
```

It exercises tool expansion, choice selection, input submission, widgets, and
footer status using `Tilde.Core.Session` helpers such as `toggle_expand/2` and
`select_choice/3`.

The default TypeScript entry registers the `TildeConsole` hook. Click-based
expansion works without JavaScript hooks; the hook adds focused-block `ctrl+o`,
slash suggestion keyboard navigation, input sizing, and scroll sticking.

## TUI renderer

Tilde includes terminal-renderer building blocks for the SSH demo path:

```elixir
Tilde.Renderer.TUI.render_to_string(session, width: 80)
```

The TUI renderer uses `Inspect.Algebra` for width-aware layout and Elixir's
built-in `IO.ANSI` helpers for ANSI styling. ANSI remains renderer output only;
semantic events, blocks, runs, and streams do not store terminal escapes.

Minimal key decoding is available through `Tilde.Core.Keys`:

```elixir
Tilde.Core.Keys.decode(<<15>>) #=> :toggle_expand
```

## SSH demo

Tilde can expose semantic sessions over SSH as terminal UIs:

```elixir
# iex -S mix
{:ok, _pid} = Tilde.Transport.SSH.Demo.start_link(port: 4022)
```

Then connect with OpenSSH:

```sh
ssh tilde@localhost -p 4022 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null
```

Password:

```text
printed by mix tilde.demo; override with --password or TILDE_DEMO_PASSWORD
```

The demo generates a PEM RSA host key through the configured
`Tilde.Transport.SSH.KeyProvider`; the default `Tilde.Transport.SSH.KeyProvider.PublicKey` uses
Erlang/OTP `:public_key` and writes to `_build/tilde_ssh/system`. It does not
call `ssh-keygen`. The SSH shell is not an OS shell or PTY emulator. SSH is only
the transport for the semantic Tilde session rendered through
`Tilde.Renderer.TUI`. The demo uses `Tilde.Transport.SSH.Channel`, an
`:ssh_server_channel` implementation, so it can observe PTY allocation, shell
requests, channel data, and window resize events directly.

Initial keys:

```text
ctrl+o     toggle first tool block
r          redraw when the prompt is empty
q          quit when the prompt is empty
enter      submit prompt text as a semantic user message
backspace  edit prompt text
esc        clear prompt text
ctrl+c     clear prompt text, or quit when empty
```

In the SSH demo, each new connection starts on the index. Opening or attaching
to a named session shares the submitted transcript while prompt edits remain
local to each SSH client.

Use slash commands to control sessions:

```text
/session        show the current semantic session id and mode
/attach name    explicitly attach this SSH client to a named shared session
/detach         leave an attached session and return to the index
/new name       create/navigate to a named isolated web session
```

After `/attach name`, multiple SSH clients and `/tilde/name` can observe the same
submitted transcript, while each SSH client keeps its own prompt buffer.

The SSH path has been dogfooded with OpenSSH through tmux. Terminal output uses
CRLF line endings over SSH so remote terminals return to column zero correctly.

## Standalone mirrored demo

Run the web + SSH demo with one command:

```sh
mix tilde.demo
```

Then open the LiveView DOM renderer:

```text
http://localhost:4000/tilde
```

And connect the SSH/TUI renderer:

```sh
ssh tilde@localhost -p 4022 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null
```

Password: printed by `mix tilde.demo`; override with `--password` or `TILDE_DEMO_PASSWORD`.

By default, each SSH connection starts on the shared index. Open a session from
the list or run `/attach <session_id>` in SSH/TUI and open `/tilde/<session_id>`
in the browser. Named sessions are stored through `Tilde.Session.Registry`
without creating dynamic atoms. Use `--web-port`, `--ssh-port`, or `--password`
to customize the task.

The demo includes a small renderer-neutral slash command layer through
`Tilde.Command`. Commands such as `/help`, `/session`, `/attach <name>`,
`/detach`, `/clear`, `/compact`, and `/new [name]` are parsed from semantic input
and work across LiveView and TUI/SSH.
The web demo also exposes a “New isolated session” link, which is UI sugar over
`/new`.

## LLM runtime

Tilde keeps its semantic session/event model as the source of truth and delegates
model/runtime orchestration to a behaviour-backed LLM boundary. The default
backend is `Tilde.Runtime.LLM.Provider.Jido`, which uses `Tilde.Agent` (`Jido.AI.Agent`) with
ReqLLM/OpenRouter. The agent includes a safe demo tool, `Tilde.Tools.UtcNow`,
whose Jido tool lifecycle is projected back into Tilde semantic tool events. The
demo enables automatic assistant replies; set `OPENROUTER_API_KEY` to use the
configured model:

```elixir
config :tilde,
  llm_backend: Tilde.Runtime.LLM.Provider.Jido,
  llm_model: "openrouter:~anthropic/claude-haiku-latest"
```

Without an API key, submissions remain semantic user messages and the demo shows
a clear configuration message instead of crashing. The standalone public demo
uses optional Hammer/ETS rate limiting for LLM submissions and caps retained
session events so shared demo history stays bounded.

## Mirrored sessions

See [`docs/architecture.md`](docs/architecture.md) for the full web/SSH/TUI
architecture, including interactions, index behavior, `/attach`, `/detach`,
local prompt buffers, and normal-screen append rendering.

`Tilde.Session.Server` owns a single semantic `%Tilde.Core.Session{}` process and
broadcasts `{:tilde_session_updated, session_id, session}` to subscribers.
Renderers can subscribe to the same server to mirror one session without sharing
DOM, ANSI, PTY, or terminal state:

```elixir
{:ok, _pid} = Tilde.Session.Server.start_link(name: :demo, session: Tilde.Demo.Live.demo_session())
Tilde.Session.Server.subscribe(:demo)
Tilde.Session.Server.apply_key(:demo, {:text, "h"})
Tilde.Session.Server.append_event(:demo, Tilde.input_submitted("hello"))
```

`Tilde.Demo.Live` uses named sessions for `/tilde/:session_id`.
`Tilde.Transport.SSH.Demo` starts on the index, can attach a channel to a named
session with `/attach <session_id>`, and returns to the index with `/detach`.

## Display state

Expansion is renderer state, not content mutation:

```elixir
Tilde.display_changed("tool_1", %{expanded?: true})
```

A web renderer might expose this through a button and `ctrl+o`; a future ANSI
renderer can expose the same action as a terminal keybinding.

## Minimal examples

Create and render a semantic session as text:

```elixir
session =
  Tilde.session(id: "demo")
  |> Tilde.Core.Session.append_event(Tilde.user_message("Run tests"))
  |> Tilde.Core.Session.append_event(Tilde.assistant_done("I'll run `mix test`."))

Tilde.Renderer.Text.render(session.transcript)
```

Own a shared semantic session process:

```elixir
{:ok, _pid} = Tilde.Session.Server.start_link(name: :demo, session: Tilde.session(id: "demo"))
Tilde.Session.Server.append_event(:demo, Tilde.input_submitted("hello"))
```

Mount the demo LiveView in a Phoenix router:

```elixir
live "/tilde", Tilde.Demo.Live, :index
live "/tilde/:session_id", Tilde.Demo.Live, :index
```

Start the SSH demo transport:

```elixir
{:ok, _pid} = Tilde.Transport.SSH.Demo.start_link(port: 4022, password: "use-a-long-random-password")
```

## Development

```sh
mix deps.get
mix ci
```
