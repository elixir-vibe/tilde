defmodule Tilde.Block do
  @moduledoc """
  Semantic transcript block.

  Blocks are the stable document model derived from events. They intentionally do
  not contain ANSI escape sequences, terminal cursor mutations, or DOM markup.
  """

  alias Tilde.{Action, Choice, Display, Run, Stream}

  @type kind :: :message | :tool | :status | :error | :choice
  @type role :: :user | :assistant | :system | :tool
  @type status :: :queued | :running | :streaming | :done | :success | :error | :cancelled

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          role: role() | nil,
          format: :plain | :markdown | :runs,
          source: String.t(),
          runs: [Run.t()],
          name: String.t() | nil,
          status: status() | nil,
          args: map(),
          streams: [Stream.t()],
          result: term(),
          choice: Choice.t() | nil,
          display: Display.t(),
          actions: [Action.t()],
          metadata: map()
        }

  defstruct id: nil,
            kind: :message,
            role: nil,
            format: :plain,
            source: "",
            runs: [],
            name: nil,
            status: nil,
            args: %{},
            streams: [],
            result: nil,
            choice: nil,
            display: %Display{},
            actions: [],
            metadata: %{}

  @doc "Creates a message block."
  @spec message(String.t(), atom(), String.t(), keyword()) :: t()
  def message(id, role, source, opts \\ []) when is_binary(source) do
    %__MODULE__{
      id: id,
      kind: :message,
      role: role,
      format: Keyword.get(opts, :format, :markdown),
      source: source,
      runs: Keyword.get(opts, :runs, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc "Appends text to a message block."
  @spec append_text(t(), String.t()) :: t()
  def append_text(%__MODULE__{kind: :message} = block, text) when is_binary(text) do
    %{block | source: block.source <> text}
  end

  @doc "Creates a choice block."
  @spec choice(String.t(), Choice.t(), keyword()) :: t()
  def choice(id, %Choice{} = choice, opts \\ []) do
    %__MODULE__{
      id: id,
      kind: :choice,
      choice: choice,
      actions: choice.actions,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc "Creates a tool block."
  @spec tool(String.t(), String.t(), map(), keyword()) :: t()
  def tool(id, name, args \\ %{}, opts \\ []) do
    %__MODULE__{
      id: id,
      kind: :tool,
      name: name,
      status: Keyword.get(opts, :status, :running),
      args: args,
      streams: Keyword.get(opts, :streams, []),
      display: Keyword.get(opts, :display, %Display{}),
      actions: Keyword.get(opts, :actions, default_tool_actions()),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc "Appends a chunk to a named stream, creating it if necessary."
  @spec append_stream(t(), atom(), String.t()) :: t()
  def append_stream(%__MODULE__{kind: :tool} = block, kind, chunk) when is_binary(chunk) do
    %{block | streams: upsert_stream(block.streams, kind, chunk), status: :streaming}
  end

  @doc "Marks a tool block as done and stores its result."
  @spec finish_tool(t(), atom(), term()) :: t()
  def finish_tool(%__MODULE__{kind: :tool} = block, status, result \\ nil) do
    %{block | status: status, result: result}
  end

  @doc "Updates display preferences for a block."
  @spec update_display(t(), map()) :: t()
  def update_display(%__MODULE__{} = block, attrs) do
    %{block | display: Display.merge(block.display, attrs)}
  end

  @doc "Toggles expanded display state for a block."
  @spec toggle_expand(t()) :: t()
  def toggle_expand(%__MODULE__{} = block) do
    %{block | display: Display.toggle(block.display)}
  end

  @doc "Selects an option in a choice block."
  @spec select_choice(t(), String.t()) :: t()
  def select_choice(%__MODULE__{kind: :choice, choice: %Choice{} = choice} = block, option_id) do
    %{block | choice: Choice.select(choice, option_id)}
  end

  def select_choice(%__MODULE__{} = block, _option_id), do: block

  defp upsert_stream([], kind, chunk), do: [Stream.new(kind) |> Stream.append(chunk)]

  defp upsert_stream([%Stream{kind: kind} = stream | rest], kind, chunk) do
    [Stream.append(stream, chunk) | rest]
  end

  defp upsert_stream([stream | rest], kind, chunk) do
    [stream | upsert_stream(rest, kind, chunk)]
  end

  defp default_tool_actions do
    [
      Action.new(:toggle_expand, "Expand", key: "ctrl+o"),
      Action.new(:copy_output, "Copy output"),
      Action.new(:retry, "Retry")
    ]
  end
end
