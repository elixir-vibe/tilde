defmodule Tilde.SSH.Channel do
  @moduledoc """
  `:ssh_server_channel` implementation for the Tilde SSH demo.

  This channel handles SSH session events directly: PTY allocation, shell start,
  resize events, channel data, EOF, and close. It renders semantic Tilde session
  state through `Tilde.TUI.Renderer` and sends the resulting ANSI bytes over the
  SSH channel.
  """

  @behaviour :ssh_server_channel

  alias Tilde.{Block, Session, SessionServer}
  alias Tilde.TUI.{Controller, Keys, Renderer, ViewRenderer}
  alias Tilde.View.Builder

  defstruct connection_ref: nil,
            channel_id: nil,
            width: 100,
            height: 30,
            session: nil,
            session_server: nil,
            streaming?: false

  @type t :: %__MODULE__{
          connection_ref: term(),
          channel_id: term(),
          width: pos_integer(),
          height: pos_integer(),
          session: Session.t() | nil,
          session_server: SessionServer.name() | nil,
          streaming?: boolean()
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
    old_session = state.session
    state = %{state | session: session}

    state =
      cond do
        stale_session?(old_session, session) -> state
        session == old_session -> state
        true -> render_change(state, old_session)
      end

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
    render(state)
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _connection_ref, {:data, _channel_id, 0, data}}, state) do
    old_session = state.session

    state
    |> apply_keys(Keys.decode_many(data))
    |> case do
      {:cont, state} ->
        state = render_change(state, old_session)
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

    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _connection_ref, {:eof, channel_id}}, state),
    do: {:stop, channel_id, state}

  def handle_ssh_msg({:ssh_cm, _connection_ref, {:closed, channel_id}}, state),
    do: {:stop, channel_id, state}

  def handle_ssh_msg(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

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

  defp render_change(%__MODULE__{} = state, %Session{} = old_session) do
    cond do
      input_only_update?(old_session, state.session) ->
        render_prompt(state)
        state

      assistant_stream_finished?(old_session, state.session, state) ->
        append_prompt(state)
        %{state | streaming?: false}

      status_only_update?(old_session, state.session) ->
        state

      new_blocks = new_blocks(old_session, state.session) ->
        append_blocks(state, new_blocks, prompt?: prompt_after_blocks?(state.session, new_blocks))
        %{state | streaming?: streaming_blocks?(new_blocks)}

      delta = assistant_delta(old_session, state.session) ->
        append_text(state, delta)
        %{state | streaming?: true}

      true ->
        state
    end
  end

  defp render_change(%__MODULE__{} = state, _old_session) do
    render(state)
    state
  end

  defp stale_session?(%Session{} = current, %Session{} = incoming) do
    length(incoming.events) < length(current.events)
  end

  defp stale_session?(_current, _incoming), do: false

  defp input_only_update?(%Session{} = old, %Session{} = new) do
    old.input != new.input and
      old.transcript == new.transcript and
      old.widgets == new.widgets and
      old.statuses == new.statuses
  end

  defp status_only_update?(%Session{} = old, %Session{} = new) do
    old.input == new.input and old.transcript == new.transcript and old.widgets == new.widgets and
      old.statuses != new.statuses
  end

  defp assistant_stream_finished?(%Session{} = old, %Session{} = new, %__MODULE__{
         streaming?: true
       }) do
    Map.has_key?(old.statuses, "model") and not Map.has_key?(new.statuses, "model")
  end

  defp assistant_stream_finished?(_old, _new, _state), do: false

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

  defp streaming_blocks?(blocks) do
    Enum.any?(blocks, &match?(%Block{kind: :message, role: :assistant}, &1))
  end

  defp prompt_after_blocks?(%Session{} = session, blocks) do
    not streaming_blocks?(blocks) and not Map.has_key?(session.statuses, "model")
  end

  defp render(%__MODULE__{connection_ref: nil}), do: :ok
  defp render(%__MODULE__{channel_id: nil}), do: :ok

  defp render(%__MODULE__{} = state) do
    bytes =
      state.session
      |> Renderer.render(width: state.width, height: state.height, clear?: false)
      |> IO.iodata_to_binary()

    :ssh_connection.send(state.connection_ref, state.channel_id, bytes)
  end

  defp render_prompt(%__MODULE__{connection_ref: nil}), do: :ok
  defp render_prompt(%__MODULE__{channel_id: nil}), do: :ok

  defp render_prompt(%__MODULE__{} = state) do
    send_bytes(state, [
      "\r",
      IO.ANSI.clear_line(),
      Renderer.render_prompt(state.session, ansi: true)
    ])
  end

  defp append_blocks(%__MODULE__{} = state, blocks, opts) do
    prompt? = Keyword.get(opts, :prompt?, true)

    content =
      blocks
      |> Enum.map_join("\n\n", &render_block(&1, state))
      |> terminal_newlines()

    send_bytes(state, [
      "\r",
      IO.ANSI.clear_line(),
      content,
      if(prompt?, do: ["\r\n\r\n", Renderer.render_prompt(state.session, ansi: true)], else: "")
    ])
  end

  defp append_text(%__MODULE__{} = state, text) do
    send_bytes(state, terminal_newlines(text))
  end

  defp append_prompt(%__MODULE__{} = state) do
    send_bytes(state, ["\r\n\r\n", Renderer.render_prompt(state.session, ansi: true)])
  end

  defp render_block(%Block{kind: :message, role: :user, source: source}, _state), do: source

  defp render_block(%Block{kind: :message, role: role, source: source}, _state) do
    [IO.ANSI.faint(), to_string(role), IO.ANSI.normal(), "\n", source]
    |> IO.iodata_to_binary()
  end

  defp render_block(%Block{} = block, %__MODULE__{} = state) do
    block
    |> Builder.block()
    |> ViewRenderer.render(state.width, ansi: true)
  end

  defp terminal_newlines(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.replace("\n", "\r\n")
  end

  defp send_bytes(%__MODULE__{connection_ref: nil}, _bytes), do: :ok
  defp send_bytes(%__MODULE__{channel_id: nil}, _bytes), do: :ok

  defp send_bytes(%__MODULE__{} = state, bytes) do
    :ssh_connection.send(state.connection_ref, state.channel_id, IO.iodata_to_binary(bytes))
  end

  defp close(%__MODULE__{connection_ref: nil}), do: :ok
  defp close(%__MODULE__{channel_id: nil}), do: :ok

  defp close(%__MODULE__{} = state) do
    :ssh_connection.exit_status(state.connection_ref, state.channel_id, 0)
    :ssh_connection.send_eof(state.connection_ref, state.channel_id)
  end

  defp non_zero(0, fallback), do: fallback
  defp non_zero(value, _fallback), do: value

  defp normalize_args([opts]) when is_list(opts), do: opts
  defp normalize_args(opts) when is_list(opts), do: opts
  defp normalize_args(_args), do: []
end
