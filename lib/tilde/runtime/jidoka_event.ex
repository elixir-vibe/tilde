defmodule Tilde.Runtime.JidokaEvent do
  @moduledoc """
  Projects canonical Jidoka runtime events into Tilde runtime-facing values.

  This module is the small boundary where `%Jidoka.Event{}` data is interpreted
  for Tilde's semantic session loop. It does not mutate sessions or append Tilde
  events; it only extracts deltas, operation tool events, terminal text, failure
  reasons, and sanitized terminal metadata.
  """

  alias Tilde.Core.AgentRuntime
  alias Tilde.Runtime.Metadata
  alias Tilde.Tool.Event, as: ToolEvent

  @doc "Returns a normalized LLM delta as `{chunk_type, text}` or `nil`."
  @spec delta(Jidoka.Event.t()) :: {:content | :thinking, String.t()} | nil
  def delta(%Jidoka.Event{event: :llm_delta, data: data}) do
    chunk_type = field(data, :chunk_type, :content)
    text = field(data, :delta, "")

    cond do
      chunk_type in [:content, "content"] and is_binary(text) and text != "" ->
        {:content, text}

      chunk_type in [:thinking, "thinking"] and is_binary(text) and text != "" ->
        {:thinking, text}

      true ->
        nil
    end
  end

  def delta(%Jidoka.Event{}), do: nil

  @doc "Returns a Tilde tool-started event from a Jidoka operation-started event."
  @spec operation_started(Jidoka.Event.t()) :: ToolEvent.t() | nil
  def operation_started(%Jidoka.Event{event: :effect_started, effect_kind: :operation} = event) do
    if operation_arguments?(event.data) do
      ToolEvent.started(
        id: event.effect_id || field(event.data, :tool_call_id),
        name: event.operation || field(event.data, :tool_name, "tool"),
        args: field(event.data, :arguments, %{})
      )
    end
  end

  def operation_started(%Jidoka.Event{}), do: nil

  @doc "Returns a Tilde tool-finished event from a Jidoka operation terminal event."
  @spec operation_finished(Jidoka.Event.t()) :: ToolEvent.t() | nil
  def operation_finished(
        %Jidoka.Event{event: event_name, effect_kind: :operation, data: data} = event
      )
      when event_name in [:effect_completed, :effect_failed] do
    case operation_result(data) do
      nil ->
        nil

      raw_result ->
        ToolEvent.finished(
          id: event.effect_id || field(data, :tool_call_id),
          status: tool_status(raw_result),
          output: tool_result(raw_result)
        )
    end
  end

  def operation_finished(%Jidoka.Event{}), do: nil

  @doc "Returns terminal assistant text from a Jidoka turn-finished event."
  @spec terminal_text(Jidoka.Event.t()) :: String.t()
  def terminal_text(%Jidoka.Event{event: :turn_finished, data: data}) do
    data |> field(:result, "") |> to_string()
  end

  @doc "Returns the public failure reason from a Jidoka turn-failed event."
  @spec failure_reason(Jidoka.Event.t()) :: term()
  def failure_reason(%Jidoka.Event{event: :turn_failed, data: data}) do
    field(data, :error, data)
  end

  @doc "Returns sanitized terminal metadata for a Jidoka turn-finished event."
  @spec terminal_metadata(AgentRuntime.t() | nil, Jidoka.Event.t()) :: map()
  def terminal_metadata(runtime, %Jidoka.Event{event: :turn_finished, data: data}) do
    runtime
    |> runtime_snapshot()
    |> Map.merge(
      reject_nil_values(%{
        usage: field(data, :usage),
        termination_reason: field(data, :termination_reason),
        thinking_content: field(data, :thinking_content),
        reasoning_details: field(data, :reasoning_details),
        jidoka: field(data, :jidoka)
      })
    )
    |> reject_nil_values()
    |> Metadata.sanitize()
  end

  def terminal_metadata(_runtime, %Jidoka.Event{}), do: %{}

  @doc "Fetches a field from atom-keyed or string-keyed Jidoka event data."
  @spec field(map() | term(), atom(), term()) :: term()
  def field(data, key, default \\ nil)

  def field(data, key, default) when is_atom(key) and is_map(data) do
    Map.get(data, key, Map.get(data, Atom.to_string(key), default))
  end

  def field(_data, _key, default), do: default

  defp operation_arguments?(data) when is_map(data), do: field(data, :arguments) != nil
  defp operation_arguments?(_data), do: false

  defp operation_result(data) when is_map(data) do
    field(data, :result) || field(data, :error) || field(data, :output)
  end

  defp operation_result(_data), do: nil

  defp tool_status({:ok, _result, _meta}), do: :success
  defp tool_status({:ok, _result}), do: :success
  defp tool_status(_other), do: :error

  defp tool_result({:ok, result, _meta}), do: result
  defp tool_result({:ok, result}), do: result
  defp tool_result(result), do: result

  defp runtime_snapshot(nil), do: %{}

  defp runtime_snapshot(%AgentRuntime{} = runtime) do
    runtime
    |> AgentRuntime.dump()
    |> Map.take([:run_id, :request_id, :checkpoint_token, :iteration])
    |> reject_nil_values()
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
