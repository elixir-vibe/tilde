defmodule Tilde.Transport.Live.Outcome do
  @moduledoc "Applies transport-neutral interaction outcomes to a LiveView socket."

  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2]

  alias Phoenix.LiveView.Socket
  alias Tilde.Core.Interaction.Outcome

  @type session_path_fun :: (String.t() -> String.t())

  @spec apply(Socket.t(), [Outcome.t()], keyword()) :: Socket.t()
  def apply(%Socket{} = socket, outcomes, opts \\ []) when is_list(outcomes) do
    session_path = Keyword.get(opts, :session_path, &default_session_path/1)
    index_path = Keyword.get(opts, :index_path, "/")

    Enum.reduce(outcomes, socket, fn
      %Outcome{type: :complete_input, payload: %{input: input}}, socket ->
        push_event(socket, "tilde:input_completed", %{insert: input})

      %Outcome{type: :open_session, payload: %{id: id}}, socket ->
        push_navigate(socket, to: session_path.(id))

      %Outcome{type: :open_index}, socket ->
        push_navigate(socket, to: index_path)

      %Outcome{type: :show_session_info}, socket ->
        socket
    end)
  end

  defp default_session_path(id), do: "/tilde/#{id}"
end
