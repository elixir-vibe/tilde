defmodule Tilde.Runtime.LLM.Provider.Jido.HistoryRequestTransformer do
  @moduledoc false

  @doc "Injects Tilde's persisted transcript history into standalone Jido ReAct requests."
  def transform_request(%{messages: request_messages} = request, _state, _config, runtime_context)
      when is_list(request_messages) and is_map(runtime_context) do
    history = Map.get(runtime_context, :messages, [])

    {:ok, %{request | messages: merge_messages(request_messages, history)}}
  end

  def transform_request(request, _state, _config, _runtime_context), do: {:ok, request}

  defp merge_messages(request_messages, []), do: request_messages

  defp merge_messages(request_messages, history) when is_list(history) do
    {system, rest} = Enum.split_while(request_messages, &(message_role(&1) == :system))
    system ++ normalize_history(history) ++ rest
  end

  defp normalize_history(history) do
    Enum.flat_map(history, fn
      %{role: role, content: content}
      when role in [:user, :assistant, :system] and is_binary(content) ->
        [%{role: role, content: content}]

      %{"role" => role, "content" => content} when is_binary(content) ->
        case role_atom(role) do
          nil -> []
          role -> [%{role: role, content: content}]
        end

      _other ->
        []
    end)
  end

  defp message_role(%{role: role}) when is_atom(role), do: role
  defp message_role(%{"role" => role}) when is_binary(role), do: role_atom(role)
  defp message_role(_message), do: nil

  defp role_atom("user"), do: :user
  defp role_atom("assistant"), do: :assistant
  defp role_atom("system"), do: :system
  defp role_atom(_role), do: nil
end
