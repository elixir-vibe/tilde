defmodule Tilde.SSH.Channel do
  @moduledoc """
  `:ssh_server_channel` implementation for the Tilde SSH demo.

  This channel handles SSH session events directly: PTY allocation, shell start,
  resize events, channel data, EOF, and close. It renders semantic Tilde session
  state through `Tilde.TUI.Renderer` and sends the resulting ANSI bytes over the
  SSH channel.
  """

  @behaviour :ssh_server_channel

  alias Tilde.{Block, Input, Session, SessionRegistry, SessionServer}
  alias Tilde.TUI.{Controller, Keys, Renderer, ViewRenderer}
  alias Tilde.View.Builder

  defstruct connection_ref: nil,
            channel_id: nil,
            width: 100,
            height: 30,
            session: nil,
            session_server: nil,
            session_mode: :private,
            session_id: nil,
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
          streaming?: boolean()
        }

  @impl true
  def init(args) do
    opts = normalize_args(args)

    session_server = Keyword.get(opts, :session_server)
    session_mode = Keyword.get(opts, :session_mode, :private)

    session = Keyword.get_lazy(opts, :session, &Tilde.Live.Demo.demo_session/0)

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
    %{state | session: session, session_id: session.id}
  end

  defp route_session(%__MODULE__{} = state) do
    attach_session(state, private_session_id(), announce?: false)
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
      SessionServer.ensure_started(server, session: Tilde.Live.Demo.demo_session(id: session_id))

    session = SessionServer.subscribe(server)

    state = %{
      state
      | session_server: server,
        session: session,
        session_id: session_id,
        streaming?: false
    }

    if Keyword.get(opts, :announce?, true), do: render_attached_session(state)
    state
  end

  defp attach_command(input) when is_binary(input) do
    case Tilde.Command.parse(input) do
      {:ok, %Tilde.Command{name: "attach", args: args}} when args != "" ->
        {:ok, SessionRegistry.normalize_id(args)}

      {:ok, %Tilde.Command{name: "attach"}} ->
        {:ok, "shared"}

      _other ->
        :error
    end
  end

  defp attach_command(_input), do: :error

  defp submit_local_input(
         server,
         %__MODULE__{session: %Session{input: %Input{value: value}}} = state
       ) do
    if String.trim(value) == "" do
      {:cont, {:cont, state}}
    else
      session =
        SessionServer.update_session(server, fn session ->
          session
          |> Session.append_event(Tilde.input_submitted(value))
          |> Session.put_status("last input", compact(value))
        end)

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

  defp apply_local_prompt_key(%__MODULE__{} = state, :tab) do
    case Tilde.Command.completion(state.session.input.value) do
      nil -> {:cont, {:cont, state}}
      completion -> put_local_input(state, Input.put_value(state.session.input, completion))
    end
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :backspace) do
    put_local_input(state, Input.backspace(state.session.input))
  end

  defp apply_local_prompt_key(%__MODULE__{} = state, :cancel) do
    put_local_input(state, Input.clear(state.session.input))
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
      state.session
      |> Session.put_input(input)
      |> put_local_command_suggestions(input.value)

    {:cont, {:cont, %{state | session: session}}}
  end

  defp put_local_command_suggestions(%Session{} = session, value) do
    case Tilde.Command.suggestions(value) do
      nil ->
        %{
          session
          | widgets:
              Map.new(session.widgets, fn {placement, widgets} ->
                {placement, Enum.reject(widgets, &(&1.id == "command-suggestions"))}
              end)
        }

      suggest ->
        Session.put_widget(
          session,
          Tilde.Widget.new("command-suggestions", :above_input, suggest)
        )
    end
  end

  defp preserve_local_prompt(
         %Session{} = incoming,
         %Session{input: %Input{value: value}} = current
       )
       when value != "" do
    %{incoming | input: current.input, widgets: current.widgets}
  end

  defp preserve_local_prompt(%Session{} = incoming, _current), do: incoming

  defp compact(input) do
    input
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 80)
  end

  defp apply_keys(%__MODULE__{session_server: nil} = state, keys) do
    apply_local_keys(state, keys)
  end

  defp apply_keys(%__MODULE__{session_server: server} = state, keys) do
    Enum.reduce_while(keys, {:cont, state}, fn
      :enter, {:cont, state} ->
        case attach_command(state.session.input.value) do
          {:ok, session_id} -> {:cont, {:cont, attach_session(state, session_id)}}
          :error -> submit_local_input(server, state)
        end

      key, {:cont, state} ->
        apply_local_prompt_key(state, key)
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

  defp render_attached_session(%__MODULE__{} = state) do
    snapshot =
      state.session
      |> Renderer.render(width: state.width, height: state.height, clear?: false)
      |> IO.iodata_to_binary()

    send_bytes(state, [
      "\r",
      IO.ANSI.clear_line(),
      IO.ANSI.faint(),
      "attached session: #{state.session_id}",
      IO.ANSI.normal(),
      "\r\n\r\n",
      snapshot
    ])
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
