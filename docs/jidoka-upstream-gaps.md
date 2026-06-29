# Jidoka upstream gap inventory

Tilde should dogfood Jidoka's abstractions instead of growing parallel runtime
semantics. When Tilde needs to compensate for missing or ambiguous runtime
concepts, treat that as pressure to improve Jidoka upstream unless the concern is
purely console/UI projection.

## Boundary rule

Keep Tilde responsible for:

- durable semantic console events and transcript projection
- workspace, review, palette, shortcuts, and renderers
- `Jidoka.Event` / `Jidoka.Turn.Result` projection through
  `Tilde.Runtime.JidokaEvent`
- sanitizing runtime-originated metadata before persistence through
  `Tilde.Runtime.Metadata`

Push upstream to Jidoka when the missing concept is about:

- agent/turn lifecycle semantics
- canonical runtime event taxonomy
- effect, approval, cancellation, resume, journal, or snapshot contracts
- test harness capabilities for deterministic runtime behavior

## Current gaps

### 1. Cancellation is represented as an error-shaped terminal event

Current Tilde pressure:

- Fake Jidoka LLM capabilities can return `{:error, :cancelled}`.
- Jidoka currently surfaces that through `:turn_failed` with error-shaped data.
- Tilde must classify cancellation in `Tilde.Runtime.JidokaEvent.cancelled?/1` by
  inspecting several possible data shapes:
  - `%{reason: :cancelled}`
  - `%{"reason" => "cancelled"}`
  - `%{error: :cancelled}`
  - `%{"error" => "cancelled"}`

Why this belongs upstream:

Cancellation is a turn lifecycle outcome, not a console rendering concern. Jidoka
should expose a canonical cancellation semantic so consumers do not infer it from
error payload shapes.

Possible upstream shape:

- introduce canonical `:turn_cancelled` events, or
- introduce a structured terminal result/status such as
  `%Jidoka.Turn.Result{status: :cancelled}`, or
- normalize `{:error, :cancelled}` into a typed cancellation error/event with a
  stable predicate such as `Jidoka.Event.cancelled?/1`.

Tilde follow-up after upstream support:

- replace `Tilde.Runtime.JidokaEvent.cancelled?/1` payload inspection with the
  upstream predicate/event kind.
- update cancellation tests to assert the canonical Jidoka cancellation flow.

### 2. Terminal LLM metadata still requires consumer-side projection choices

Current Tilde pressure:

- Tilde projects usage, termination reason, thinking content, reasoning details,
  journal summaries, and operation summaries out of Jidoka terminal events.
- Tilde also sanitizes metadata to avoid persisting pids, refs, functions, or raw
  structs.

Why this may belong upstream:

Jidoka owns journals, effect results, and turn result metadata. A stable public
"safe metadata projection" helper would let consumers persist runtime metadata
without duplicating journal/operation summarization rules.

Possible upstream shape:

- `Jidoka.Turn.Result.metadata_summary/1`
- `Jidoka.Event.terminal_metadata/1`
- explicit JSON-safe metadata contract for terminal events and snapshots

Tilde follow-up after upstream support:

- make `Tilde.Runtime.JidokaEvent.terminal_metadata/2` mostly add Tilde runtime
  snapshot fields and delegate Jidoka metadata summarization upstream.

### 3. Snapshot tokens are Jidoka-specific but Tilde serializes projection details

Current Tilde pressure:

- Tilde persists hibernation tokens as `jidoka:snapshot:v1:` strings.
- Tilde stores only sanitized agent runtime metadata and uses
  `%Tilde.Core.AgentRuntime{}` as the durable console-side summary.

Why this may belong upstream:

Jidoka owns snapshot/resume semantics. Consumers need a small stable public
contract for snapshot token validation, display-safe metadata, and cancellation of
checkpointed turns.

Possible upstream shape:

- `Jidoka.Runtime.AgentSnapshot.token?/1`
- `Jidoka.Runtime.AgentSnapshot.summary/1`
- a documented checkpoint metadata map safe for persistence

Tilde follow-up after upstream support:

- replace string-prefix checks in tests with upstream token predicates.
- keep `%Tilde.Core.AgentRuntime{}` as Tilde's UI/session summary only.

### 4. Deterministic test seams are useful but still low-level

Current Tilde pressure:

- Tests inject Jidoka `llm:` functions through ephemeral `llm_opts`.
- Some stream tests use arity-3 LLM functions to access Jidoka stream sinks.

Why this may belong upstream:

Deterministic fake capabilities are a runtime/harness concern. Jidoka could
provide standard test helpers for final responses, operation decisions, streamed
deltas, hibernation, cancellation, and failures.

Possible upstream shape:

- `Jidoka.TestLLM.final/2`
- `Jidoka.TestLLM.operation/2`
- `Jidoka.TestLLM.stream/2`
- `Jidoka.TestRuntime.cancelled/0`

Tilde follow-up after upstream support:

- replace Tilde-local fake LLM helper functions with upstream Jidoka test helpers
  while preserving Tilde integration tests.

## First upstream candidate

Start with cancellation semantics. It is the clearest runtime lifecycle gap and
already causes Tilde to inspect error payload shapes. The target outcome is that a
consumer can distinguish cancellation from failure without knowing how a
capability encoded the cancellation internally.
