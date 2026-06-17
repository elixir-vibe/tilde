# Tilde architecture

Tilde is a semantic agent console. Sessions, transcripts, index state, widgets,
and interactions are the source of truth; DOM, ANSI, SSH channel data, and cells
are renderer projections.

## Layers

```text
Transport raw input
  LiveView events / browser hook events / SSH bytes
    ↓
Tilde.Core.Interaction
  ephemeral user intent: input changed, accept suggestion, submit, interrupt
    ↓
Core state/controllers
  Tilde.Core.Index / Tilde.Core.Session / Tilde.Core.Controller
    ↓
Durable session events and command effects
  Tilde.Core.Event / Tilde.Command.Effect
    ↓
Semantic UI composition
  Tilde.Core.Widget / Tilde.Core.Suggest / transcript blocks
    ↓
Renderer adapters
  LiveView DOM / TUI ANSI / SSH normal-screen output / text
```

`Tilde.Core.Event` is durable history. `Tilde.Core.Interaction` is not durable;
it is the shared transport-neutral event model for user intent.

## Session source of truth

`Tilde.Core.Session` owns semantic state:

- append-only events
- reduced transcript blocks
- generic status values for footer/demo labels
- one strict `Tilde.Core.AssistantTurn` lifecycle
- command suggestions and widgets
- metadata

Renderers derive output from this state. ANSI escape sequences, DOM nodes,
terminal cursor movement, and SSH channel details are renderer concerns only.

## Assistant lifecycle

Assistant progress is not encoded in generic statuses and must not be inferred
from display strings such as `"thinking…"`.

`Tilde.Core.Session` owns a `Tilde.Core.AssistantTurn` with explicit phases:

```text
:idle -> :waiting -> :streaming | :tooling | :thinking -> :done
                                |-> :error
                                |-> :cancelled
```

The lifecycle is driven by semantic events:

- `:assistant_turn_started`
- `:assistant_delta`
- `:tool_started`
- `:assistant_turn_finished`
- `:assistant_turn_error`
- `:assistant_turn_cancelled`

Renderers use helpers such as `Session.assistant_waiting?/1` and
`Session.assistant_active?/1`. Generic `statuses` remain available for unrelated
labels but do not own assistant lifecycle.

## Index/home surface

The web root and SSH/TUI entry point are an index/home surface, not a hidden demo
session. `Tilde.Core.Index` owns input, selection, command suggestions, and real
session suggestions from `Tilde.Session.Registry`.

`Tilde.Index.View` composes that state into `Tilde.Core.Widget` trees. LiveView
and SSH/TUI render the same widget composition through their adapters.

## Interactions

Transports translate raw input into `Tilde.Core.Interaction` before applying
index behavior. Applying an interaction returns updated core state plus
transport-neutral `Tilde.Core.Interaction.Effect` values such as:

- `:complete_input`
- `:open_session`

LiveView maps these to `push_event/3` or navigation. SSH maps them to local input
updates or session attachment.

Session prompt key handling still flows through `Tilde.Core.Controller`; it is
the terminal-oriented controller for decoded `Tilde.Core.Keys` values.

## Commands

`Tilde.Command` parses slash commands and delegates argument suggestions to the
owning command module. Command modules own their argument domains:

- `Tilde.Command.Builtin.Attach` suggests real attachable sessions.
- `Tilde.Command.Builtin.New` suggests session-name hints.

`Tilde.Command.Spec` is registry metadata only.

Transport-specific handling of command effects is limited to effects that must
leave the current renderer context, such as opening or attaching to a session.
Pure session effects are applied through `Tilde.Command.apply_effects/2`.

## Web sessions

Named web sessions live at:

```text
/tilde/:session_id
```

A named session is backed by `Tilde.Session.Registry` and a
`Tilde.Session.Server` process. Session ids are normalized and do not create
dynamic atoms.

## SSH sessions

SSH/TUI starts on the index. Opening a session attaches the channel to a named
`Tilde.Session.Server`.

After attach:

- submitted transcript events are shared
- assistant/tool output is shared
- each SSH client keeps a local prompt buffer
- one attached client typing does not mutate another client's prompt

`/detach` returns to the index.

## SSH normal-screen rendering

The public SSH demo uses the terminal normal screen. It does not use alternate
screen, terminal emulation, full-screen repainting, clear-screen/home redraws for
normal updates, or mouse capture.

SSH updates are append-oriented:

- simple prompt typing echoes appended characters
- backspace/non-append edits redraw only the prompt line
- new transcript blocks append
- assistant deltas append as received
- tool stream deltas append with stream labels on first chunks
- prompt is reprinted when needed after model streaming

## Semantic UI composition

`Tilde.Core.Widget` is the shared semantic composition unit. HEEx templates can
compile to widgets through `Tilde.Template.to_widgets!/2`. Cells are low-level
TUI/TTY projection primitives only.

```text
HEEx semantic source
  ↓
Tilde.Template.Compiler
  ↓
Tilde.Core.Widget
  ↓
LiveView DOM or TUI cells/ANSI
```

## Roadmap

- Continue moving semantic templates toward widget output first.
- Keep Live/SSH files as transport adapters, not domain behavior owners.
- Keep command argument suggestions in command modules.
- Keep session preview extraction in `Tilde.Session.Summary`.
