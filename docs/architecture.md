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
it is the shared transport-neutral event model for user intent in both index and
session mode.

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

## Durable storage

`Tilde.Storage` is the storage boundary. Core session/event modules stay
storage-neutral. The QuackDB implementation uses `Tilde.Storage.Repo`, Ecto
schemas, and Ecto migrations under `priv/repo/migrations`.

Storage tables follow these roles:

- `tilde_sessions` stores durable session metadata.
- `tilde_session_events` is the canonical ordered event log for full resume.
- `tilde_session_blocks` is a searchable projection derived from events.
- `tilde_session_state` stores resumable draft/input state, not transcript truth.

`Tilde.Core.Event` remains the only semantic event type. `Tilde.Storage.EventPolicy`
only decides which existing events belong in the durable log. Draft-only
`:input_changed` events are not stored canonically; the latest draft lives in
`tilde_session_state`.

`Tilde.Session.Loader` is the restore boundary for opening sessions. It loads a
persisted session through `Tilde.Storage.load_session/1` when a storage adapter is
configured, otherwise it creates a fresh session. Live and SSH session opening go
through this loader so storage writes have a matching resume path.

`Tilde.Session.Summary.list/0` combines live registry summaries with persisted
storage summaries. Live sessions win when the same id exists in both places.

`Tilde.Storage.Setup.migrate/1` runs the storage migrations through Ecto. QuackDB
integration tests are tagged `:quackdb_integration` and excluded by default; run
them with `TILDE_QUACKDB_INTEGRATION=1` plus either `QUACKDB_TEST_URI` /
`QUACKDB_TEST_TOKEN` for an external Quack server or `QUACKDB_TEST_DUCKDB=managed`
where the managed DuckDB Quack server is supported.

QuackDB-backed storage must use Ecto, Ecto migrations, and QuackDB's Ecto/query
DSL. Do not use raw SQL strings or ad hoc SQL fragments for Tilde storage.

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

The index is navigation/discovery only. Selecting a session opens that session.
Every other submitted action creates or opens a real session and submits the
input there; arbitrary prompts and transcript-producing commands must not execute
against the index itself.

`Tilde.Index.View` composes that state into `Tilde.Core.Widget` trees. LiveView
and SSH/TUI render the same widget composition through their adapters.

## Interactions

Transports translate raw input into `Tilde.Core.Interaction` before applying
index or session behavior. Applying an interaction returns updated core state
plus transport-neutral `Tilde.Core.Interaction.Outcome` values such as:

- `:complete_input`
- `:open_session`
- `:open_index`
- `:show_session_info`

`Tilde.Transport.Live.Interaction` and `Tilde.Transport.SSH.Interaction` perform
transport input translation. `Tilde.Transport.Live.Outcome` maps outcomes to
`push_event/3` or navigation. `Tilde.Transport.SSH.Outcome` maps outcomes through
SSH handlers for local input updates, session attachment, index return, or an
inline session-info display.

Session prompt key handling can still flow through `Tilde.Core.Controller.apply_key/2`
for decoded `Tilde.Core.Keys` values; transports that already have semantic
intent should prefer `Controller.apply_interaction/2`.

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
/sessions/:session_id
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

`Tilde.Transport.SSH.LocalPrompt` owns the local prompt behavior for attached SSH
clients so channel protocol code does not own shared-session prompt isolation.

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

`Tilde.Transport.SSH.Rendering` owns pure normal-screen rendering iodata. The SSH
channel owns protocol callbacks and sending bytes, not the shape of rendered
sessions, prompts, blocks, and stream chunks.

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

## Agent runtime

ReqLLM, Jido, and Jido.AI are mandatory dependencies. Tilde should not compile a
reduced model-free agent/runtime surface behind conditional `Code.ensure_loaded?`
branches. Missing API keys or provider configuration are runtime errors surfaced
as assistant events, not alternate compilation modes.

Current state: `Tilde.Session.AgentLoop` owns assistant start, streaming,
cancellation, tool projection, and queued prompt continuation. Runtime queuing is
explicit in session-server state through `pending_prompts`; the loop does not scan
durable history to decide what to run next. It still uses one stream task per
active loop; the Jidoka provider runs `Jidoka.turn/3` / `Jidoka.resume/2` and
streams canonical `Jidoka.Event` structs, while Tilde projects those runtime
events into durable console events.

Migration plan to a normal agent loop:

1. Introduce a session-owned agent runtime state alongside `prompt_task` and
   `prompt_ref` (`active_agent`, stream owner/ref, current tool context, and last
   submitted prompt).
2. Move prompt submission into a single lifecycle entry point that records the
   user event, starts/continues the agent loop, and wires Jidoka/ReqLLM callbacks
   for deltas, thinking, operation started/finished, usage, completion, and
   errors.
3. Keep the loop alive for tool/assistant iterations until the provider reports a
   terminal result, rather than treating every model call as a standalone response.
4. Project every loop transition back into `Tilde.Core.Event` only:
   assistant lifecycle events, assistant deltas, tool events, status/usage events,
   and final assistant messages.
5. Make cancellation stop both the active agent and prompt task, emit a
   cancellation event, and clear runtime state without losing durable transcript
   events.
6. Preserve index/session transport neutrality: Live, SSH, and TUI continue to
   submit `Tilde.Core.Interaction` values and receive semantic session updates;
   none of them own agent-loop behavior.
7. Add regression tests for multi-step tool loops, multiple queued user prompts,
   cancellation, provider errors, and resume/listing behavior.

## Test support

Transport drivers cover user-observable parity across LiveView, TUI, browser,
and SSH surfaces. Semantic assertion helpers cover core interaction outcomes and
widget trees without going through DOM, ANSI, or browser rendering. Add new test
support inside the project's established helper namespaces instead of creating
flat ad hoc helper files.

## Roadmap

- Continue moving semantic templates toward widget output first.
- Keep Live/SSH files as transport adapters, not domain behavior owners.
- Keep command argument suggestions in command modules.
- Keep session preview extraction in `Tilde.Session.Summary`.
