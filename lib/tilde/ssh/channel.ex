defmodule Tilde.SSH.Channel do
  @moduledoc """
  `:ssh_server_channel` implementation for the Tilde SSH demo.

  This channel handles SSH session events directly: PTY allocation, shell start,
  resize events, channel data, EOF, and close. It renders semantic Tilde session
  state through `Tilde.TUI.Renderer` and sends the resulting ANSI bytes over the
  SSH channel.
  """

  @behaviour :ssh_server_channel

  alias Tilde.{Session, SessionServer}
  alias Tilde.TUI.{Controller, Keys, Renderer}

  defstruct connection_ref: nil,
            channel_id: nil,
            width: 100,
            height: 30,
            session: nil,
            session_server: nil,
            alternate_screen?: false

  @type t :: %__MODULE__{
          connection_ref: term(),
          channel_id: term(),
          width: pos_integer(),
          height: pos_integer(),
          session: Session.t() | nil,
          session_server: SessionServer.name() | nil,
          alternate_screen?: boolean()
        }

  @impl true
  def init(args) do
    opts = normalize_args(args)

    session_server = Keyword.get(opts, :session_server)

    session =
      if session_server do
        SessionServer.get_session(session_server)
      else
        Keyword.get_lazy(opts, :session, &Tilde.Live.Demo.demo_session/0)
      end

    {:ok,
     %__MODULE__{
       width: Keyword.get(opts, :width, 100),
       height: Keyword.get(opts, :height, 30),
       session: session,
       session_server: session_server
     }}
  end

  @impl true
  def handle_msg({:ssh_channel_up, channel_id, connection_ref}, state) do
    if state.session_server, do: SessionServer.subscribe(state.session_server)
    {:ok, %{state | channel_id: channel_id, connection_ref: connection_ref}}
  end

  def handle_msg({:tilde_session_updated, _session_id, %Session{} = session}, state) do
    state = %{state | session: session}
    render(state)
    {:ok, state}
  end

  def handle_msg(_message, state), do: {:ok, state}

  @impl true
  def handle_ssh_msg({:ssh_cm, connection_ref, {:pty, channel_id, want_reply, pty}}, state) do
    {_term, width, height, _pixel_width, _pixel_height, _modes} = pty
    :ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)

    {:ok,
     %{
       state
       | connection_ref: connection_ref,
         channel_id: channel_id,
         width: non_zero(width, state.width),
         height: non_zero(height, state.height)
     }}
  end

  def handle_ssh_msg({:ssh_cm, connection_ref, {:shell, channel_id, want_reply}}, state) do
    :ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)

    state = %{state | connection_ref: connection_ref, channel_id: channel_id}
    state = enter_alternate_screen(state)
    render(state)
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _connection_ref, {:data, _channel_id, 0, data}}, state) do
    state
    |> apply_keys(Keys.decode_many(data))
    |> case do
      {:cont, state} ->
        render(state)
        {:ok, state}

      {:halt, state} ->
        close(state)
        {:stop, state.channel_id, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, connection_ref,
         {:window_change, channel_id, width, height, _pixel_width, _pixel_height}},
        state
      ) do
    state = %{
      state
      | connection_ref: connection_ref,
        channel_id: channel_id,
        width: non_zero(width, state.width),
        height: non_zero(height, state.height)
    }

    render(state)
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _connection_ref, {:eof, channel_id}}, state),
    do: {:stop, channel_id, state}

  def handle_ssh_msg({:ssh_cm, _connection_ref, {:closed, channel_id}}, state),
    do: {:stop, channel_id, state}

  def handle_ssh_msg(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    leave_alternate_screen(state)
    :ok
  end

  defp apply_keys(%__MODULE__{session_server: nil} = state, keys) do
    apply_local_keys(state, keys)
  end

  defp apply_keys(%__MODULE__{session_server: server} = state, keys) do
    Enum.reduce_while(keys, {:cont, state}, fn key, {:cont, state} ->
      case SessionServer.apply_key(server, key) do
        {:cont, session} -> {:cont, {:cont, %{state | session: session}}}
        {:halt, session} -> {:halt, {:halt, %{state | session: session}}}
      end
    end)
  end

  defp apply_local_keys(%__MODULE__{} = state, keys) do
    Enum.reduce_while(keys, {:cont, state}, fn key, {:cont, state} ->
      case Controller.apply_key(state.session, key) do
        {:cont, session} -> {:cont, {:cont, %{state | session: session}}}
        {:halt, session} -> {:halt, {:halt, %{state | session: session}}}
      end
    end)
  end

  defp render(%__MODULE__{connection_ref: nil}), do: :ok
  defp render(%__MODULE__{channel_id: nil}), do: :ok

  defp render(%__MODULE__{} = state) do
    bytes =
      state.session
      |> Renderer.render(width: state.width, height: state.height)
      |> IO.iodata_to_binary()

    :ssh_connection.send(state.connection_ref, state.channel_id, bytes)
  end

  defp close(%__MODULE__{connection_ref: nil}), do: :ok
  defp close(%__MODULE__{channel_id: nil}), do: :ok

  defp close(%__MODULE__{} = state) do
    leave_alternate_screen(state)
    :ssh_connection.exit_status(state.connection_ref, state.channel_id, 0)
    :ssh_connection.send_eof(state.connection_ref, state.channel_id)
  end

  defp enter_alternate_screen(%__MODULE__{alternate_screen?: true} = state), do: state

  defp enter_alternate_screen(%__MODULE__{} = state) do
    send_bytes(state, "\e[?1049h")
    %{state | alternate_screen?: true}
  end

  defp leave_alternate_screen(%__MODULE__{alternate_screen?: false}), do: :ok
  defp leave_alternate_screen(%__MODULE__{} = state), do: send_bytes(state, "\e[?1049l")

  defp send_bytes(%__MODULE__{connection_ref: nil}, _bytes), do: :ok
  defp send_bytes(%__MODULE__{channel_id: nil}, _bytes), do: :ok

  defp send_bytes(%__MODULE__{} = state, bytes),
    do: :ssh_connection.send(state.connection_ref, state.channel_id, bytes)

  defp non_zero(0, fallback), do: fallback
  defp non_zero(value, _fallback), do: value

  defp normalize_args([opts]) when is_list(opts), do: opts
  defp normalize_args(opts) when is_list(opts), do: opts
  defp normalize_args(_args), do: []
end
