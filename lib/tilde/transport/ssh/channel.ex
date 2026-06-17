defmodule Tilde.Transport.SSH.Channel do
  @moduledoc """
  `:ssh_server_channel` implementation for the Tilde SSH demo.

  This channel handles SSH session events directly: PTY allocation, shell start,
  resize events, channel data, EOF, and close. It renders semantic Tilde session
  state through `Tilde.Renderer.TUI` and sends the resulting ANSI bytes over the
  SSH channel.
  """

  @behaviour :ssh_server_channel

  alias Tilde.Command, as: SlashCommand
  alias Tilde.Core.{Block, Controller, Input, Keys, Session}
  alias Tilde.Renderer.TUI
  alias Tilde.Renderer.TUI.ViewRenderer
  alias Tilde.Session.Registry, as: SessionRegistry
  alias Tilde.Session.Server, as: SessionServer
  alias Tilde.Transport.SSH.Delta

  defstruct connection_ref: nil,
            channel_id: nil,
            width: 100,
            height: 30,
            session: nil,
            session_server: nil,
            session_mode: :private,
            session_id: nil,
            attached?: false,
            streaming?: false

  @type t :: %__MODULE__{
          connection_ref: term(),
          channel_id: term(),
          width: pos_integer(),
          height: pos_integer(),
          session: Session.t() | nil,
          session_server: SessionServer.name() | nil,
          session_mode: :private | :shared,
          session_id: String.t() | nil,
          attached?: boolean(),
          streaming?: boolean()
        }

  @impl true
  def init(args) do
    opts = normalize_args(args)

    session_server = Keyword.get(opts, :session_server)
    session_mode = Keyword.get(opts, :session_mode, :private)

    session = Keyword.get_lazy(opts, :session, &Tilde.Demo.Live.demo_session/0)

    {:ok,
     %__MODULE__{
       width: Keyword.get(opts, :width, 100),
       height: Keyword.get(opts, :height, 30),
       session: session,
       session_server: session_server,
       session_mode: session_mode,
       session_id: session.id
     }}
  end

  @impl true
  def handle_msg({:ssh_channel_up, channel_id, connection_ref}, state) do
    {:ok, %{state | channel_id: channel_id, connection_ref: connection_ref}}
  end

  def handle_msg({:tilde_session_updated, _session_id, %Session{} = session}, state) do
    old_session = state.session
    session = preserve_local_prompt(session, old_session)
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

    state =
      state
      |> Map.merge(%{connection_ref: connection_ref, channel_id: channel_id})
      |> route_session()

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

  defp route_session(%__MODULE__{session_mode: :shared, session_server: server} = state)
       when not is_nil(server) do
    session = SessionServer.subscribe(server)
    %{state | session: session, session_id: session.id, attached?: true}
  end

  defp route_session(%__MODULE__{} = state) do
    attach_session(state, private_session_id(), announce?: false, attached?: false)
  end

  defp private_session_id do
    "ssh-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp session_server_for(session_id) do
    {:ok, _pid} = SessionRegistry.ensure_started()
    SessionRegistry.via(session_id)
  end

  defp attach_session(%__MODULE__{} = state, session_id, opts \\ []) do
    session_id = SessionRegistry.normalize_id(session_id)
    old_server = state.session_server
    server = session_server_for(session_id)

    if old_server && old_server != server do
      SessionServer.unsubscribe(old_server)
    end

    {:ok, _pid} =
      SessionServer.ensure_started(server,
        session: Tilde.Demo.Live.demo_session(id: session_id)
      )

    session = SessionServer.subscribe(server)

    state = %{
      state
      | session_server: server,
        session: session,
        session_id: session_id,
        attached?: Keyword.get(opts, :attached?, true),
        streaming?: false
    }

    if Keyword.get(opts, :announce?, true),
      do: render_session_snapshot(state, Keyword.get(opts, :label, "attached session"))

    state
  end

  defp detach_session(%__MODULE__{} = state) do
    attach_session(state, private_session_id(),
      attached?: false,
      label: "detached to private session"
    )
  end

  defp show_session_info(%__MODULE__{} = state) do
    state = clear_local_prompt(state)
    render_session_info(state)
    state
  end

  defp clear_local_prompt(%__MODULE__{} = state) do
    session = Session.append_event(state.session, Tilde.input_changed(""))

    %{state | session: session}
  end

  defp submit_local_input(
         server,
         %__MODULE__{session: %Session{input: %Input{value: value}}} = state
       ) do
    if String.trim(value) == "" do
      {:cont, {:cont, state}}
    else
      session =
        SessionServer.update_session(
          server,
          &Session.append_event(&1, Tilde.input_submitted(value))
        )

      {:cont, {:cont, %{state | session: session}}}
    end
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :quit) do
    if state.session.input.value == "" do
      {:halt, {:halt, state}}
    else
      put_local_input(state, Input.insert(state.session.input, "q"))
    end
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :redraw) do
    if state.session.input.value == "" do
      {:cont, {:cont, state}}
    else
      put_local_input(state, Input.insert(state.session.input, "r"))
    end
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, {:text, text}) do
    put_local_input(state, Input.insert(state.session.input, text))
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, key)
       when key in [:tab, :backtab, :up, :down] do
    {:cont, session} = Controller.apply_key(state.session, key)
    {:cont, {:cont, %{state | session: session}}}
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :backspace) do
    put_local_input(state, Input.backspace(state.session.input))
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :cancel) do
    {:cont, session} = Controller.apply_key(state.session, :cancel)
    {:cont, {:cont, %{state | session: session}}}
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :interrupt) do
    if state.session.input.value == "" do
      {:halt, {:halt, state}}
    else
      put_local_input(state, Input.clear(state.session.input))
    end
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :toggle_expand) do
    {:cont, session} = Controller.apply_key(state.session, :toggle_expand)
    {:cont, {:cont, %{state | session: session}}}
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, _key), do: {:cont, {:cont, state}}

  defp put_local_input(%__MODULE__{} = state, %Input{} = input) do
    session =
      Session.append_event(
        state.session,
        Tilde.input_changed(input.value, metadata: %{cursor: input.cursor})
      )

    {:cont, {:cont, %{state | session: session}}}
  end

  defp preserve_local_prompt(
         %Session{} = incoming,
         %Session{input: %Input{value: value}} = current
       )
       when value != "" do
    %{incoming | input: current.input, widgets: current.widgets}
  end

  defp preserve_local_prompt(%Session{} = incoming, _current), do: incoming

  defp apply_keys(%__MODULE__{session_server: nil} = state, keys) do
    apply_local_keys(state, keys)
  end

  defp apply_keys(%__MODULE__{session_server: server} = state, keys) do
    Enum.reduce_while(keys, {:cont, state}, fn
      :enter, {:cont, state} ->
        if Session.command_suggestions(state.session) do
          {:cont, session} = Controller.apply_key(state.session, :enter)
          {:cont, {:cont, %{state | session: session}}}
        else
          submit_or_command(server, state)
        end

      key, {:cont, state} ->
        apply_local_prompt_key(state, key)
    end)
  end

  defp submit_or_command(server, state) do
    case transport_effects(state.session.input.value, state.session) do
      [%Tilde.Command.Effect.AttachSession{id: session_id} | _effects] ->
        {:cont, {:cont, attach_session(state, session_id)}}

      [%Tilde.Command.Effect.DetachSession{} | _effects] ->
        {:cont, {:cont, detach_session(state)}}

      [%Tilde.Command.Effect.ShowSessionInfo{} | _effects] ->
        {:cont, {:cont, show_session_info(state)}}

      [%Tilde.Command.Effect.NewSession{id: session_id} | _effects] ->
        {:cont, {:cont, attach_session(state, session_id)}}

      _effects ->
        submit_local_input(server, state)
    end
  end

  defp transport_effects(input, %Session{} = session) do
    case SlashCommand.parse(input) do
      {:ok, command} -> SlashCommand.run(command, session, [])
      :error -> []
    end
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
    if assistant_stream_finished?(old_session, state.session, state) do
      append_prompt(state)
      %{state | streaming?: false}
    else
      render_delta_change(state, old_session, Delta.classify(old_session, state.session))
    end
  end

  defp render_change(%__MODULE__{} = state, _old_session) do
    render(state)
    state
  end

  defp render_delta_change(%__MODULE__{} = state, old_session, :input_only) do
    render_input_change(state, old_session)
    state
  end

  defp render_delta_change(%__MODULE__{} = state, _old_session, :status_only), do: state

  defp render_delta_change(%__MODULE__{} = state, _old_session, :redraw) do
    render(state)
    state
  end

  defp render_delta_change(%__MODULE__{} = state, _old_session, :none), do: state

  defp render_delta_change(%__MODULE__{} = state, _old_session, {:new_blocks, blocks}) do
    append_blocks(state, blocks, prompt?: prompt_after_blocks?(state.session, blocks))
    %{state | streaming?: Delta.streaming_blocks?(blocks)}
  end

  defp render_delta_change(%__MODULE__{} = state, _old_session, {:assistant_delta, delta}) do
    append_text(state, delta)
    %{state | streaming?: true}
  end

  defp render_delta_change(
         %__MODULE__{} = state,
         _old_session,
         {:tool_delta, _block, kind, delta, first?}
       ) do
    append_tool_delta(state, kind, delta, first?)
    %{state | streaming?: true}
  end

  defp render_delta_change(%__MODULE__{} = state, _old_session, {:tool_done, _block}) do
    if Session.assistant_active?(state.session),
      do: state,
      else: %{state | streaming?: false}
  end

  defp stale_session?(%Session{} = current, %Session{} = incoming) do
    length(incoming.events) < length(current.events)
  end

  defp stale_session?(_current, _incoming), do: false

  defp assistant_stream_finished?(%Session{} = old, %Session{} = new, %__MODULE__{
         streaming?: true
       }) do
    Session.assistant_active?(old) and not Session.assistant_active?(new)
  end

  defp assistant_stream_finished?(_old, _new, _state), do: false

  defp prompt_after_blocks?(%Session{} = session, blocks) do
    not Delta.streaming_blocks?(blocks) and not Session.assistant_active?(session)
  end

  defp render(%__MODULE__{connection_ref: nil}), do: :ok
  defp render(%__MODULE__{channel_id: nil}), do: :ok

  defp render(%__MODULE__{} = state) do
    bytes =
      state.session
      |> TUI.render(width: state.width, height: state.height, clear?: false)
      |> IO.iodata_to_binary()

    :ssh_connection.send(state.connection_ref, state.channel_id, bytes)
  end

  defp render_session_snapshot(%__MODULE__{} = state, label) do
    snapshot =
      state.session
      |> TUI.render(width: state.width, height: state.height, clear?: false)
      |> IO.iodata_to_binary()

    send_bytes(state, [
      "\r",
      IO.ANSI.clear_line(),
      IO.ANSI.faint(),
      label,
      ": #{state.session_id}",
      IO.ANSI.normal(),
      "\r\n\r\n",
      snapshot
    ])
  end

  defp render_session_info(%__MODULE__{} = state) do
    mode = if state.attached?, do: "attached", else: "private"

    send_bytes(state, [
      "\r",
      IO.ANSI.clear_line(),
      IO.ANSI.faint(),
      "session: ",
      IO.ANSI.normal(),
      state.session_id || state.session.id,
      "\r\n",
      IO.ANSI.faint(),
      "mode: ",
      IO.ANSI.normal(),
      mode,
      "\r\n",
      IO.ANSI.faint(),
      "web: ",
      IO.ANSI.normal(),
      "/tilde/#{state.session_id || state.session.id}",
      "\r\n",
      IO.ANSI.faint(),
      "commands: ",
      IO.ANSI.normal(),
      "/attach <name> · /detach · /session",
      "\r\n\r\n"
    ])
  end

  defp render_prompt(%__MODULE__{connection_ref: nil}), do: :ok
  defp render_prompt(%__MODULE__{channel_id: nil}), do: :ok

  defp render_prompt(%__MODULE__{} = state) do
    send_bytes(state, [
      "\r",
      IO.ANSI.clear_line(),
      TUI.render_prompt(state.session, ansi: true)
    ])
  end

  defp render_input_change(%__MODULE__{} = state, %Session{} = old_session) do
    case appended_prompt_delta(old_session.input, state.session.input) do
      {:ok, delta} -> send_bytes(state, delta)
      :redraw -> render_prompt(state)
    end
  end

  defp appended_prompt_delta(%Input{} = old, %Input{} = new) do
    if old.cursor == String.length(old.value) and
         new.cursor == String.length(new.value) and
         String.starts_with?(new.value, old.value) do
      {:ok, String.replace_prefix(new.value, old.value, "")}
    else
      :redraw
    end
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
      if(prompt?, do: ["\r\n\r\n", TUI.render_prompt(state.session, ansi: true)], else: "")
    ])
  end

  defp append_text(%__MODULE__{} = state, text) do
    send_bytes(state, terminal_newlines(text))
  end

  defp append_tool_delta(%__MODULE__{} = state, kind, text, true) do
    send_bytes(state, [
      "\r\n",
      IO.ANSI.faint(),
      to_string(kind),
      IO.ANSI.normal(),
      "\r\n",
      terminal_newlines(text)
    ])
  end

  defp append_tool_delta(%__MODULE__{} = state, _kind, text, false) do
    send_bytes(state, terminal_newlines(text))
  end

  defp append_prompt(%__MODULE__{} = state) do
    send_bytes(state, ["\r\n\r\n", TUI.render_prompt(state.session, ansi: true)])
  end

  defp render_block(%Block{kind: :message, role: :user, source: source}, _state), do: source

  defp render_block(%Block{kind: :message, role: role, source: source}, _state) do
    [IO.ANSI.faint(), to_string(role), IO.ANSI.normal(), "\n", source]
    |> IO.iodata_to_binary()
  end

  defp render_block(%Block{} = block, %__MODULE__{} = state) do
    block
    |> Tilde.Viewable.to_view()
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
