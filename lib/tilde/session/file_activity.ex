defmodule Tilde.Session.FileActivity do
  @moduledoc """
  Derives per-file activity from a Tilde session's semantic tool events.
  """

  alias Tilde.Core.{Event, Session}

  @type state :: :read | :modified
  @type t :: %{optional(String.t()) => state()}

  @read_tools MapSet.new(["read"])
  @write_tools MapSet.new(["edit", "write"])

  @doc "Returns file activity for files read or modified by the session."
  @spec from_session(Session.t()) :: t()
  def from_session(%Session{} = session) do
    session |> Session.events() |> Enum.reduce(%{}, &apply_event/2)
  end

  defp apply_event(%Event{type: :tool_started, name: name, args: args}, activity)
       when is_binary(name) and is_map(args) do
    cond do
      MapSet.member?(@write_tools, name) -> put_activity(activity, args, :modified)
      MapSet.member?(@read_tools, name) -> put_activity(activity, args, :read)
      true -> activity
    end
  end

  defp apply_event(_event, activity), do: activity

  defp put_activity(activity, args, state) do
    case path_arg(args) do
      nil -> activity
      path -> Map.update(activity, path, state, &stronger_state(&1, state))
    end
  end

  defp path_arg(%{path: path}) when is_binary(path), do: path
  defp path_arg(%{"path" => path}) when is_binary(path), do: path
  defp path_arg(_args), do: nil

  defp stronger_state(:modified, _state), do: :modified
  defp stronger_state(_current, :modified), do: :modified
  defp stronger_state(_current, :read), do: :read
end
