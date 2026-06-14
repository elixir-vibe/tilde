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
- `Tilde.Live.Run` — semantic inline rendering for bold, underline, code, links, and tones

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
choice blocks, widgets, input, and footer/statusline content. They emit ordinary
LiveView events such as `tilde:toggle_expand`; parent LiveViews decide how to
apply those events to session/transcript state.

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
