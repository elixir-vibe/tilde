defmodule Tilde do
  @moduledoc """
  Semantic agent console core.

  Tilde models a pi-like agent console without making ANSI, VT100 state, DOM, or
  a character grid the source of truth. The durable layer is an append-only event
  log; transcripts, compact tool widgets, Markdown views, LiveView components,
  and future TUI adapters are derived from semantic data.
  """

  alias Tilde.Core.{Block, Choice, Event, Session, Transcript, Widget}

  @doc "Creates a user message event."
  @spec user_message(String.t(), keyword()) :: Event.t()
  def user_message(text, opts \\ []) when is_binary(text) do
    Event.new(:user_message, Keyword.put(opts, :text, text))
  end

  @doc "Creates an assistant streaming delta event."
  @spec assistant_delta(String.t(), keyword()) :: Event.t()
  def assistant_delta(text, opts \\ []) when is_binary(text) do
    Event.new(:assistant_delta, Keyword.put(opts, :text, text))
  end

  @doc "Creates a completed assistant message event."
  @spec assistant_done(String.t(), keyword()) :: Event.t()
  def assistant_done(text, opts \\ []) when is_binary(text) do
    Event.new(:assistant_done, Keyword.put(opts, :text, text))
  end

  @doc "Creates an input-changed event."
  @spec input_changed(String.t(), keyword()) :: Event.t()
  def input_changed(text, opts \\ []) when is_binary(text) do
    Event.new(:input_changed, Keyword.put(opts, :text, text))
  end

  @doc "Creates an input-submitted event."
  @spec input_submitted(String.t(), keyword()) :: Event.t()
  def input_submitted(text, opts \\ []) when is_binary(text) do
    Event.new(:input_submitted, Keyword.put(opts, :text, text))
  end

  @doc "Creates a status-changed event. Pass `nil` to clear the status."
  @spec status_changed(String.t(), term(), keyword()) :: Event.t()
  def status_changed(name, value, opts \\ []) when is_binary(name) do
    Event.new(:status_changed, opts |> Keyword.put(:name, name) |> Keyword.put(:text, value))
  end

  @doc "Creates a visible context-compaction summary event."
  @spec context_compacted(String.t(), keyword()) :: Event.t()
  def context_compacted(summary, opts \\ []) when is_binary(summary) do
    Event.new(:context_compacted, Keyword.put(opts, :text, summary))
  end

  @doc "Creates an event marking the assistant turn as waiting for first output."
  @spec assistant_turn_started(keyword()) :: Event.t()
  def assistant_turn_started(opts \\ []), do: Event.new(:assistant_turn_started, opts)

  @doc "Creates an event marking the assistant turn as finished."
  @spec assistant_turn_finished(keyword()) :: Event.t()
  def assistant_turn_finished(opts \\ []), do: Event.new(:assistant_turn_finished, opts)

  @doc "Creates an event marking the assistant turn as failed."
  @spec assistant_turn_error(term(), keyword()) :: Event.t()
  def assistant_turn_error(reason, opts \\ []),
    do: Event.new(:assistant_turn_error, Keyword.put(opts, :result, reason))

  @doc "Creates an event marking the assistant turn as cancelled."
  @spec assistant_turn_cancelled(keyword()) :: Event.t()
  def assistant_turn_cancelled(opts \\ []), do: Event.new(:assistant_turn_cancelled, opts)

  @doc "Creates a tool-started event."
  @spec tool_started(String.t(), map(), keyword()) :: Event.t()
  def tool_started(name, args \\ %{}, opts \\ []) when is_binary(name) and is_map(args) do
    Event.new(:tool_started, opts |> Keyword.put(:name, name) |> Keyword.put(:args, args))
  end

  @doc "Creates a tool stream chunk event."
  @spec tool_stream(String.t(), atom(), String.t(), keyword()) :: Event.t()
  def tool_stream(tool_call_id, stream, chunk, opts \\ [])
      when is_binary(tool_call_id) and is_atom(stream) and is_binary(chunk) do
    Event.new(
      :tool_stream,
      opts
      |> Keyword.put(:tool_call_id, tool_call_id)
      |> Keyword.put(:stream, stream)
      |> Keyword.put(:chunk, chunk)
    )
  end

  @doc "Creates a tool completion event."
  @spec tool_done(String.t(), atom(), term(), keyword()) :: Event.t()
  def tool_done(tool_call_id, status \\ :success, result \\ nil, opts \\ [])
      when is_binary(tool_call_id) and is_atom(status) do
    Event.new(
      :tool_done,
      opts
      |> Keyword.put(:tool_call_id, tool_call_id)
      |> Keyword.put(:status, status)
      |> Keyword.put(:result, result)
    )
  end

  @doc "Creates an event that changes only display state."
  @spec display_changed(String.t(), map(), keyword()) :: Event.t()
  def display_changed(block_id, display, opts \\ [])
      when is_binary(block_id) and is_map(display) do
    Event.new(
      :block_display_changed,
      opts
      |> Keyword.put(:block_id, block_id)
      |> Keyword.put(:display, display)
    )
  end

  @doc "Creates an empty semantic console session."
  @spec session(keyword()) :: Session.t()
  def session(opts \\ []), do: Session.new(opts)

  @doc "Creates a widget for a non-transcript UI region."
  @spec widget(String.t(), Widget.placement(), term(), keyword()) :: Widget.t()
  def widget(id, placement, content, opts \\ []), do: Widget.new(id, placement, content, opts)

  @doc "Creates choice state."
  @spec choice(String.t(), [Choice.option_input()], keyword()) :: Choice.t()
  def choice(question, options, opts \\ []), do: Choice.new(question, options, opts)

  @doc "Creates a transcript choice block."
  @spec choice_block(String.t(), Choice.t(), keyword()) :: Block.t()
  def choice_block(id, %Choice{} = choice, opts \\ []), do: Block.choice(id, choice, opts)

  @doc "Reduces events into a transcript."
  @spec transcript([Event.t()]) :: Transcript.t()
  def transcript(events), do: Transcript.from_events(events)
end
