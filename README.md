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

- `Tilde.Event` — append-only console events
- `Tilde.Transcript` — reducer from events to blocks
- `Tilde.Block` — semantic transcript block
- `Tilde.Stream` — lossless tool output streams
- `Tilde.Display` — compact/expanded display state, including `ctrl+o`
- `Tilde.Action` — semantic actions for renderers
- `Tilde.Run` — inline text marks such as bold and underline
- `Tilde.ToolView` — compact/expanded derived tool widget data with stream identity and metadata rows
- `Tilde.Renderer.Text` — plain text renderer
- `Tilde.Renderer.JSON` — JSON-compatible map renderer
- `Tilde.Session` — event log, transcript, widgets, statuses, and metadata
- `Tilde.Widget` — non-transcript UI regions such as above/below input and footer
- `Tilde.Choice` — semantic choice/approval state
- `Tilde.Live.*` — LiveView components in the same package
- `Tilde.Markdown` — behaviour-backed Markdown rendering facade
- `Tilde.Markdown.Backend` / `Tilde.Markdown.MDEx` — Markdown backend behaviour and MDEx implementation
- `Tilde.Live.Markdown` — LiveView Markdown renderer with plain-text fallback
- `Tilde.Live.Run` — semantic inline rendering for bold, underline, code, links, and tones
- `Tilde.TUI.*` — Inspect.Algebra + `IO.ANSI` terminal renderer building blocks
- `Tilde.SSH.*` — Erlang/OTP SSH demo server using generated `:public_key` host keys
- `Tilde.SSH.KeyProvider` / `Tilde.SSH.KeyProvider.PublicKey` — SSH host key provider behaviour and default implementation

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

## LiveView

Tilde includes a LiveView renderer namespace in the same package:

```elixir
import Tilde.Live.Console

~H"""
<.console session={@session} />
"""
```

For default styling, include the CSS returned by:

```elixir
Tilde.Live.Styles.css()
```

The Live components render semantic DOM for transcript blocks, tool widgets,
choice blocks, widgets, input, and footer/statusline content. Markdown message
source is rendered through the configured `Tilde.Markdown.Backend`; the default
`Tilde.Markdown.MDEx` backend uses MDEx's safe policy that omits raw HTML.
Components emit ordinary LiveView events such as `tilde:toggle_expand`; parent
LiveViews decide how to apply those events to session/transcript state.

A self-contained dogfood demo LiveView is included:

```elixir
# router.ex
live "/tilde", Tilde.Live.Demo
```

It exercises tool expansion, choice selection, input submission, widgets, and
footer status using `Tilde.Session` helpers such as `toggle_expand/2` and
`select_choice/3`.

For keyboard expansion, copy `Tilde.Live.Hooks.js()` into your LiveSocket assets
and register the exported `TildeConsole` hook. Click-based expansion works
without JavaScript hooks; the hook adds focused-block `ctrl+o`.

## TUI renderer

Tilde includes terminal-renderer building blocks for the SSH demo path:

```elixir
Tilde.TUI.Renderer.render_to_string(session, width: 80)
```

The TUI renderer uses `Inspect.Algebra` for width-aware layout and Elixir's
built-in `IO.ANSI` helpers for ANSI styling. ANSI remains renderer output only;
semantic events, blocks, runs, and streams do not store terminal escapes.

Minimal key decoding is available through `Tilde.TUI.Keys`:

```elixir
Tilde.TUI.Keys.decode(<<15>>) #=> :toggle_expand
```

## SSH demo

Tilde can expose the same semantic demo session over SSH as a terminal UI:

```elixir
# iex -S mix
{:ok, _pid} = Tilde.SSH.Demo.start_link(port: 4022)
```

Then connect with OpenSSH:

```sh
ssh tilde@localhost -p 4022 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null
```

Password:

```text
tilde
```

The demo generates a PEM RSA host key through the configured
`Tilde.SSH.KeyProvider`; the default `Tilde.SSH.KeyProvider.PublicKey` uses
Erlang/OTP `:public_key` and writes to `_build/tilde_ssh/system`. It does not
call `ssh-keygen`. The SSH shell is not an OS shell or PTY emulator. SSH is only
the transport for the semantic Tilde session rendered through
`Tilde.TUI.Renderer`. The demo uses `Tilde.SSH.Channel`, an
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

Prompt edits are stored as `Tilde.Input` state and `:input_changed` /
`:input_submitted` events. Submitting input appends a user message to the same
semantic transcript rendered by LiveView, TUI, and SSH.

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

Password: `tilde`.

By default, the web and SSH renderers share the same `Tilde.SessionServer`, so
input submitted over SSH appears in the web session and LiveView events mutate
the same semantic session. The standalone demo also supports isolated web-only
sessions at `/tilde/:session_id`; these are named through `Tilde.SessionRegistry`
without creating dynamic atoms. Use `--web-port`, `--ssh-port`, or `--password`
to customize the task.

## LLM runtime

Tilde keeps its semantic session/event model as the source of truth and delegates
model/runtime orchestration to a behaviour-backed LLM boundary. The default
backend is `Tilde.LLM.Jido`, which uses `Tilde.Agent` (`Jido.AI.Agent`) with
ReqLLM/OpenRouter. The agent includes a safe demo tool, `Tilde.Tools.UtcNow`,
whose Jido tool lifecycle is projected back into Tilde semantic tool events. The
demo enables automatic assistant replies; set `OPENROUTER_API_KEY` to use the
configured model:

```elixir
config :tilde,
  llm_backend: Tilde.LLM.Jido,
  llm_model: "openrouter:~anthropic/claude-haiku-latest"
```

Without an API key, submissions remain semantic user messages and the demo shows
a clear configuration message instead of crashing. The standalone public demo
uses optional Hammer/ETS rate limiting for LLM submissions and caps retained
session events so shared demo history stays bounded.

## Mirrored sessions

`Tilde.SessionServer` owns a single semantic `%Tilde.Session{}` process and
broadcasts `{:tilde_session_updated, session_id, session}` to subscribers.
Renderers can subscribe to the same server to mirror one session without sharing
DOM, ANSI, PTY, or terminal state:

```elixir
{:ok, _pid} = Tilde.SessionServer.start_link(name: :demo, session: Tilde.Live.Demo.demo_session())
Tilde.SessionServer.subscribe(:demo)
Tilde.SessionServer.apply_key(:demo, {:text, "h"})
Tilde.SessionServer.append_event(:demo, Tilde.input_submitted("hello"))
```

`Tilde.Live.Demo` and `Tilde.SSH.Demo` both default to the package-wide
`Tilde.SessionServer`, so a demo LiveView and demo SSH channel can observe and
mutate the same semantic session.

## Display state

Expansion is renderer state, not content mutation:

```elixir
Tilde.display_changed("tool_1", %{expanded?: true})
```

A web renderer might expose this through a button and `ctrl+o`; a future ANSI
renderer can expose the same action as a terminal keybinding.

## Development

```sh
mix deps.get
mix ci
```
