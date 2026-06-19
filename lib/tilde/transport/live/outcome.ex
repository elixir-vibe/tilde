defmodule Tilde.Transport.Live.Outcome do
  @moduledoc "Applies transport-neutral interaction outcomes to a LiveView socket."

  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2]

  alias Phoenix.LiveView.Socket
  alias Tilde.Core.Interaction.Outcome
  alias Tilde.Session.Registry, as: SessionRegistry
  alias Tilde.Session.Server, as: SessionServer

  @type session_path_fun :: (String.t() -> String.t())

  @spec apply(Socket.t(), [Outcome.t()], keyword()) :: Socket.t()
  def apply(%Socket{} = socket, outcomes, opts \\ []) when is_list(outcomes) do
    session_path = Keyword.get(opts, :session_path, &default_session_path/1)
    index_path = Keyword.get(opts, :index_path, "/")

    Enum.reduce(outcomes, socket, fn
      %Outcome{type: :complete_input, payload: %{input: input}}, socket ->
        push_event(socket, "tilde:input_completed", %{insert: input})

      %Outcome{type: :open_session, payload: %{id: id} = payload}, socket ->
        open_session(payload)
        push_navigate(socket, to: session_path.(id))

      %Outcome{type: :open_index}, socket ->
        push_navigate(socket, to: index_path)

      %Outcome{type: :show_session_info}, socket ->
        socket
    end)
  end

  defp open_session(%{id: id, submit: input}) when is_binary(input) do
    {:ok, _pid} = SessionRegistry.ensure_started()
    server = SessionRegistry.via(id)
    {:ok, _pid} = SessionServer.ensure_started(server, session: Tilde.session(id: id))
    SessionServer.append_event(server, Tilde.input_submitted(input))
  end

  defp open_session(_payload), do: :ok

  defp default_session_path(id), do: "/sessions/#{id}"
end
