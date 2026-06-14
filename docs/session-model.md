# Tilde session model

Tilde is a semantic console core. A session is not a terminal buffer and not a DOM tree.

```text
Tilde events
-> Tilde.Session / Tilde.Transcript
-> Tilde.View cells
-> LiveView DOM / TUI ANSI / SSH normal-screen output / JSON / text
```

## Source of truth

`Tilde.Session` owns semantic state:

- append-only events
- reduced transcript blocks
- transient status values
- widgets such as command suggestions
- metadata

Renderers derive output from this state. ANSI escape sequences, DOM nodes, terminal cursor movement, and SSH channel details are renderer concerns only.

## Web sessions

The demo web router supports named sessions:

```text
/tilde/:session_id
```

A named web session is backed by `Tilde.SessionRegistry` and a `Tilde.SessionServer` process. Session ids are normalized and do not create dynamic atoms.

## SSH sessions

Each new SSH connection creates a fresh private semantic session by default.

This prevents unrelated SSH clients from seeing each other’s prompt text, transcript, or model stream.

Explicit sharing is opt-in:

```text
/attach project-demo
```

After attach:

- submitted transcript events are shared
- assistant/tool output is shared
- each SSH client keeps a local prompt buffer
- one attached client typing does not mutate another client’s prompt

Detach returns the client to a fresh private SSH session:

```text
/detach
```

Inspect the current SSH attachment state:

```text
/session
```

It reports:

- session id
- `mode: private` or `mode: attached`
- matching web path, e.g. `/tilde/project-demo`

## Local prompt vs shared transcript

The prompt buffer is renderer-local in SSH. It is intentionally not part of the shared transcript until submitted.

```text
SSH client A prompt: local only
SSH client B prompt: local only
Enter submits -> shared transcript event
```

This avoids collaborative-editing surprises while still allowing shared transcript observation.

## SSH normal-screen rendering

The public SSH demo uses the terminal normal screen.

It does **not** use:

- alternate screen
- terminal emulation
- full-screen repainting
- clear-screen/home redraws for normal updates
- mouse capture

This preserves ordinary terminal scrollback and mouse-wheel scrolling.

SSH updates are append-oriented:

- simple prompt typing echoes appended characters
- backspace/non-append edits redraw only the prompt line
- new transcript blocks append
- assistant deltas append as received; SSH does not reflow already-written Markdown on the normal screen
- tool stream deltas append, with stream labels on first stdout/stderr/result chunks
- prompt is reprinted when needed after model streaming

## Shared view parity

LiveView, TUI, and SSH rendering use shared semantic view primitives:

```text
Tilde.View.Cell
Tilde.View.Line
Tilde.View.Text
Tilde.View.Builder
```

Compatibility Live components such as `Tilde.Live.Message`, `Tilde.Live.Tool`, and `Tilde.Live.Choice` delegate to this shared view pipeline.
