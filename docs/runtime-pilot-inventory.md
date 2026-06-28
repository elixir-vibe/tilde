# Runtime pilot inventory

This document grounds the Tilde/Jidoka/Pi runtime discussion in what Tilde already implements today. The intended sequence is:

```text
pilot in Tilde → dogfood through Tilde UI/runtime → extract stable runtime contracts → contribute to Jidoka
```

Tilde is already the pilot surface. New work should extend existing Tilde modules first instead of designing an abstract replacement core.

## Current Tilde runtime shape

```text
Live/SSH/TUI input
  → Tilde.Core.Interaction / Controller
  → Tilde.Core.Session event log
  → Tilde.Session.Server process owner
  → Tilde.Session.AgentLoop
  → Tilde.Runtime.LLM backend
  → provider runtime events
  → Tilde.Runtime.Event normalization
  → Tilde.Core.Event projection
  → Transcript / workspace / review / renderers
```

The durable session state is still Tilde-owned. Jido.AI currently owns the ReAct/model/tool runtime path behind `Tilde.Runtime.LLM.Provider.Jido`.

## Pi concepts inventory

| Pi concept | Tilde status | Current Tilde modules | Gap / pilot target |
| --- | --- | --- | --- |
| Append-only semantic session history | Implemented, linear | `Tilde.Core.Session`, `Tilde.Core.Event`, `Tilde.Core.Transcript` | Add entry identity/parentage without breaking linear projection. |
| Session tree entries (`id`/`parentId`) | Missing | none | Introduce a Tilde-local entry tree around/alongside existing events. |
| Fork/clone/tree navigation | Missing | session registry has attach/new only | Pilot branch navigation as Tilde session behavior before upstreaming any shape. |
| Labels/checkpoints | Partially present as runtime checkpoint metadata only | `Tilde.Core.AgentRuntime`, `Tilde.Session.AgentLoop.ResumeCandidate` | Add user-visible labels/checkpoints on session entries. |
| Branch summaries | Missing | none | Build after entry tree exists; summary should be a semantic entry/event. |
| Manual compaction command | Implemented | `Tilde.Command.Builtin.Compact`, `Tilde.Session.Compaction` | Harden cut rules and metadata. |
| Auto/token-threshold compaction | Missing | `Tilde.Session.Compaction` has message-count keep_recent | Add token-budget policy after tree/entry contracts are clearer. |
| Split-turn compaction | Missing | none | Only needed once effect/turn boundaries are modeled. |
| Cumulative file operation tracking in summaries | Missing/partial | `Tilde.Session.FileActivity` exists; compaction does not use it | Attach read/modified file details to compaction/branch entries. |
| Extension hook lifecycle | Not implemented as plugin host | commands/tools exist; no hook system | Pilot narrow Elixir hooks only where product needs them. |
| Tool call/result interception | Missing at Tilde layer | `Tilde.Tools.*`, `Tilde.Tool.*` | Prefer effect journal/control boundary before generic hooks. |
| Resource loading: skills/prompts/context files | Minimal/not Pi-like | commands and app config only | Defer; avoid importing product conventions before runtime core stabilizes. |
| Multiple run modes sharing one session runtime | Implemented at console level | Live, SSH/TUI, drivers, `Tilde.Session.Server` | Keep this in Tilde, not Jidoka. |

## Jidoka concepts inventory

| Jidoka concept | Tilde status | Current Tilde modules | Gap / pilot target |
| --- | --- | --- | --- |
| Agent spec / data-first agent authoring | Mostly absent | Tilde has configured backend/tools, not an agent spec | Defer until Tilde actually needs first-class agent specs. |
| Turn request/plan/result | Partial/ad hoc | `Tilde.Session.AgentLoop.Prompt`, `Run`, `State`; `Tilde.Core.AssistantTurn` | Introduce Tilde-local turn structs only around real needs. |
| Effect intent/result journal | Missing | tool events are transcript events, not journaled effects | Add a Tilde-local effect journal before trying to generalize. |
| Effect idempotency classes | Missing | none | Add only when replay/resume semantics require it. |
| Runtime event stream | Implemented via Jido.AI events, not Jidoka events | `Tilde.Runtime.LLM.Provider.Jido`, `Tilde.Session.AgentLoop` | Add a projection boundary that can later consume `Jidoka.Event`. |
| Snapshot/cursor resume | Partial | `Tilde.Core.AgentRuntime`, `ResumeCandidate`, `Run` | Current model is a checkpoint pointer, not a portable turn snapshot. |
| Human review/approval interrupts | UI review implemented; runtime approval missing | `Tilde.Core.Review`, `Tilde.Session.ReviewState`, `WorkspaceReview` | Distinguish code-review workflow from runtime operation approval. |
| Session/store | Implemented independently | `Tilde.Storage`, `Tilde.Storage.QuackDB`, `Tilde.Session.Loader` | Could later adapt to `Jidoka.Harness.Store`; not ready yet. |
| Replay diagnostics | Partial | transcript replay from events; no effect diagnostics | Build after effect journal exists. |
| Streaming helper contract | Implemented through Tilde buffering and Jido events | `Tilde.Session.Server`, `Tilde.Session.AgentLoop` | Current stream coalescing is Tilde-console-specific. |

## Current implemented subsystems

### Semantic session/event/transcript

Files:

```text
lib/tilde/core/session.ex
lib/tilde/core/event.ex
lib/tilde/core/transcript.ex
lib/tilde/core/block.ex
```

What exists:

- Linear append-only event log.
- Derived transcript blocks.
- Assistant lifecycle events.
- Tool transcript events.
- Input/draft events.
- Context compaction event.

Important constraint: renderers derive from session state; renderer state must not become source of truth.

### Session server and shared transport state

Files:

```text
lib/tilde/session/server.ex
lib/tilde/session/registry.ex
lib/tilde/session/loader.ex
lib/tilde/session/persistence.ex
```

What exists:

- One process owns a semantic session.
- Live/SSH/TUI clients can subscribe.
- Attach/new/session summaries exist.
- Persistence is called for newly appended canonical events and resumable state.
- Boot-time checkpoint resume is handled.

Gap: no tree/branch position; a session has one linear history.

### Agent loop/checkpoint resume

Files:

```text
lib/tilde/session/agent_loop.ex
lib/tilde/session/agent_loop/state.ex
lib/tilde/session/agent_loop/run.ex
lib/tilde/session/agent_loop/resume_candidate.ex
lib/tilde/core/agent_runtime.ex
```

What exists:

- Active assistant loop state.
- Prompt queueing while a turn is active.
- Stream task ownership and cancellation.
- Runtime metadata persisted in session metadata.
- Resume candidate reconstruction from persisted checkpoint metadata.
- Cancellation calls backend checkpoint cancellation when possible.

Current durable runtime metadata:

```text
active?
input_index
block_id
queue_length
run_id
request_id
checkpoint_token
iteration
```

Gap: this is a pointer to a backend checkpoint, not a portable snapshot with turn state, cursor, pending effects, and journal.

### Jido.AI-backed runtime provider

Files:

```text
lib/tilde/runtime/llm.ex
lib/tilde/runtime/llm/provider.ex
lib/tilde/runtime/llm/provider/jido.ex
lib/tilde/runtime/llm/event.ex
```

What exists:

- Small LLM facade.
- Jido.AI ReAct streaming backend.
- Provider events normalized into `Tilde.Runtime.Event`.
- Projection of request/tool/delta/checkpoint/completion/failure events into `Tilde.Core.Event`.
- Compaction summary generation via backend.

Gap: no runtime-neutral event adapter yet. A future Jidoka adapter should target this boundary, not the renderers.

### Compaction

Files:

```text
lib/tilde/session/compaction.ex
lib/tilde/command/builtin/compact.ex
```

What exists:

- `/compact` command.
- Visible compaction block.
- Latest compaction summary supersedes older summaries for model context.
- Raw transcript/event history remains visible and durable.
- LLM summary with extractive fallback.
- Basic metadata: `first_kept_block_id`, `tokens_before`, `compacted_blocks`, `custom_instructions`.

Gap: compaction is block-count based and linear. It does not yet know about tree entries, split turns, effect boundaries, or file-operation details.

### Persistence/storage

Files:

```text
lib/tilde/storage.ex
lib/tilde/storage/quackdb.ex
lib/tilde/storage/event_codec.ex
lib/tilde/storage/event_policy.ex
lib/tilde/storage/schema/*.ex
```

What exists:

- Storage boundary behavior.
- QuackDB implementation.
- Canonical event log.
- Searchable block projection.
- Session metadata/draft state.
- Loader restores session by replaying stored events and state.

Current event payload codec is Tilde-internal:

```text
erlang-term-v1
```

Gap: this is not a public/session-interchange format. That is fine for the Tilde pilot, but extraction to Jidoka would need stable schema-backed contracts.

### Workspace/file/review semantic console

Files:

```text
lib/tilde/core/workspace*.ex
lib/tilde/core/file_buffer.ex
lib/tilde/core/palette*.ex
lib/tilde/core/review*.ex
lib/tilde/runtime/workspace_files.ex
lib/tilde/runtime/workspace_review.ex
lib/tilde/session/review_state.ex
```

What exists:

- Workspace/sidebar state.
- File buffer state and paging.
- Palette files/symbols.
- Review model with comments, resolve/reopen, next/previous.
- Git/workspace-derived review generation.
- Review status persistence in session metadata.
- Live and SSH/TUI rendering/actions.

Important boundary: this should remain Tilde semantic console state, not move into Jidoka runtime core.

## Current tests proving behavior

Representative coverage:

```text
test/tilde/session/compaction_test.exs
test/tilde/session/server_test.exs
test/tilde/session/agent_loop/resume_candidate_test.exs
test/tilde/session/agent_loop/resume_start_test.exs
test/tilde/runtime/llm/resume_test.exs
test/tilde/storage/event_codec_test.exs
test/tilde/storage/quackdb_integration_test.exs
test/tilde/runtime/workspace_review_test.exs
```

The key existing tested behaviors are:

- compaction summary preserves raw visible history;
- model context uses latest summary plus kept tail;
- `/compact` appends a semantic event;
- LLM compaction summary fallback works;
- restored checkpoint metadata can resume on server startup;
- boot-time resume persists only new events and clears runtime metadata;
- cancellation clears runtime metadata and calls backend cancellation;
- QuackDB can persist/search/summarize/load sessions.

## Pilot roadmap inside Tilde

### Step 1: Entry tree shadow model

Add a Tilde-local session entry model without replacing current events immediately.

Candidate namespace:

```text
Tilde.Session.Entry
Tilde.Session.EntryTree
```

Minimum contract:

```text
id
parent_id
type
payload
timestamp
```

Initial entry types:

```text
:event
:compaction
:label
:branch_summary
:metadata
```

Projection rule: current `Tilde.Core.Session.events` remains the linear branch projection used by existing renderers.

### Step 2: Labels/checkpoints

Add user-visible labels on entries. Do this before fork/branch UI so there is something useful to navigate to.

Candidate command:

```text
/checkpoint [label]
```

### Step 3: Branch navigation and summaries

Once entry tree exists:

- navigate to an entry;
- preserve current branch with optional summary;
- append branch summary entry at the new position;
- keep current renderer projection linear.

### Step 4: Effect journal pilot

Add effect intent/result data for LLM and tool calls, initially as metadata/events projected from the existing agent loop.

Candidate namespace:

```text
Tilde.Runtime.Effect.Intent
Tilde.Runtime.Effect.Result
Tilde.Runtime.Effect.Journal
```

Do not require idempotency classes on day one. First prove stable effect identity and result recording.

### Step 5: Snapshot/cursor pilot

Replace or augment `Tilde.Core.AgentRuntime` checkpoint pointer with a serializable turn snapshot/cursor.

Candidate namespace:

```text
Tilde.Runtime.Turn.Cursor
Tilde.Runtime.Turn.Snapshot
```

This should be driven by real resume/replay failures in Tilde, not by copying Jidoka wholesale.

### Step 6: Jidoka adapter spike

Only after the above exists, build a narrow adapter:

```text
Jidoka.Event / Jidoka.Turn.Result / Jidoka.Effect.Journal
  → Tilde.Core.Event / Tilde transcript / Tilde runtime metadata
```

The adapter should exercise existing Tilde renderers unchanged.

## Extraction criteria for eventual Jidoka contribution

A concept is ready to move toward Jidoka only when all are true:

1. It is renderer-neutral.
2. It is useful outside Tilde’s Web/SSH/TUI console.
3. It has stable struct/schema semantics.
4. It has tests that do not depend on Tilde UI fixtures.
5. It improves Jidoka’s durable agent/session runtime, not just Tilde’s product UX.

Likely extraction candidates after dogfooding:

- session entry tree contract;
- branch summary contract;
- compaction entry contract;
- effect journal additions;
- snapshot/cursor improvements;
- replay diagnostics.

Likely non-candidates:

- workspace pane;
- file buffer rendering;
- review pane rendering;
- palette and shortcuts;
- LiveView/SSH/TUI transport details.
