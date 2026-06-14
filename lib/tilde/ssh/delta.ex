defmodule Tilde.SSH.Delta do
  @moduledoc """
  Classifies semantic session changes for SSH normal-screen rendering.

  The SSH renderer must avoid full-frame repainting. This module turns old/new
  semantic sessions into append-oriented changes that the channel can render
  without terminal emulation.
  """

  alias Tilde.{Block, Session, Stream}

  @type t ::
          :none
          | :status_only
          | :input_only
          | {:new_blocks, [Block.t()]}
          | {:assistant_delta, String.t()}
          | {:tool_delta, Block.t(), Stream.kind(), String.t(), boolean()}
          | {:tool_done, Block.t()}

  @doc "Classifies a session transition for append-oriented SSH rendering."
  @spec classify(Session.t(), Session.t()) :: t()
  def classify(%Session{} = old, %Session{} = new) do
    cond do
      old == new ->
        :none

      input_only?(old, new) ->
        :input_only

      status_only?(old, new) ->
        :status_only

      blocks = new_blocks(old, new) ->
        {:new_blocks, blocks}

      delta = assistant_delta(old, new) ->
        {:assistant_delta, delta}

      delta = tool_delta(old, new) ->
        delta

      done = tool_done(old, new) ->
        done

      true ->
        :none
    end
  end

  @doc "Returns true when blocks indicate an active append stream."
  @spec streaming_blocks?([Block.t()]) :: boolean()
  def streaming_blocks?(blocks) do
    Enum.any?(blocks, fn
      %Block{kind: :message, role: :assistant} -> true
      %Block{kind: :tool, status: status} when status in [:queued, :running, :streaming] -> true
      _block -> false
    end)
  end

  defp input_only?(%Session{} = old, %Session{} = new) do
    old.input != new.input and
      old.transcript == new.transcript and
      old.widgets == new.widgets and
      old.statuses == new.statuses
  end

  defp status_only?(%Session{} = old, %Session{} = new) do
    old.input == new.input and old.transcript == new.transcript and old.widgets == new.widgets and
      old.statuses != new.statuses
  end

  defp new_blocks(%Session{} = old, %Session{} = new) do
    old_count = length(old.transcript.blocks)
    new_count = length(new.transcript.blocks)

    if new_count > old_count do
      Enum.drop(new.transcript.blocks, old_count)
    else
      nil
    end
  end

  defp assistant_delta(%Session{} = old, %Session{} = new) do
    with %Block{kind: :message, role: :assistant, id: id, source: old_source} <-
           List.last(old.transcript.blocks),
         %Block{kind: :message, role: :assistant, id: ^id, source: new_source} <-
           List.last(new.transcript.blocks),
         true <- String.starts_with?(new_source, old_source),
         delta when delta != "" <- String.replace_prefix(new_source, old_source, "") do
      delta
    else
      _other -> nil
    end
  end

  defp tool_delta(%Session{} = old, %Session{} = new) do
    with {%Block{} = old_tool, %Block{} = new_tool} <- changed_tool_pair(old, new),
         {kind, delta, first?} <- stream_delta(old_tool, new_tool) do
      {:tool_delta, new_tool, kind, delta, first?}
    else
      _other -> nil
    end
  end

  defp tool_done(%Session{} = old, %Session{} = new) do
    with {%Block{status: old_status}, %Block{status: new_status} = new_tool} <-
           changed_tool_pair(old, new),
         true <- old_status in [:queued, :running, :streaming],
         true <- new_status in [:success, :done, :error, :cancelled] do
      {:tool_done, new_tool}
    else
      _other -> nil
    end
  end

  defp changed_tool_pair(%Session{} = old, %Session{} = new) do
    old_by_id = Map.new(old.transcript.blocks, &{&1.id, &1})

    Enum.find_value(new.transcript.blocks, fn
      %Block{kind: :tool, id: id} = new_tool ->
        case Map.get(old_by_id, id) do
          %Block{kind: :tool} = old_tool when old_tool != new_tool -> {old_tool, new_tool}
          _other -> nil
        end

      _block ->
        nil
    end)
  end

  defp stream_delta(%Block{} = old_tool, %Block{} = new_tool) do
    old_streams = Map.new(old_tool.streams, &{&1.kind, &1})

    Enum.find_value(new_tool.streams, fn %Stream{kind: kind} = new_stream ->
      old_text = old_streams |> Map.get(kind, Stream.new(kind)) |> Stream.text()
      new_text = Stream.text(new_stream)

      if String.starts_with?(new_text, old_text) and new_text != old_text do
        {kind, String.replace_prefix(new_text, old_text, ""), old_text == ""}
      end
    end)
  end
end
