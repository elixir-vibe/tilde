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

  alias Tilde.Core.{
    Controller,
    Index,
    Interaction,
    Keys,
    Palette,
    Review,
    Session,
    Shortcuts,
    Workspace
  }

  alias Tilde.Core.Interaction.Outcome
  alias Tilde.Runtime.{WorkspaceFiles, WorkspaceReview}
  alias Tilde.Session.Registry, as: SessionRegistry
  alias Tilde.Session.ReviewState
  alias Tilde.Session.Server, as: SessionServer
  alias Tilde.Transport.SSH.Delta
  alias Tilde.Transport.SSH.Interaction, as: SSHInteraction
  alias Tilde.Transport.SSH.LocalPrompt
  alias Tilde.Transport.SSH.Outcome, as: SSHOutcome
  alias Tilde.Transport.SSH.Rendering

  defstruct connection_ref: nil,
            channel_id: nil,
            width: 100,
            height: 30,
            session: nil,
            index: nil,
            session_server: nil,
            session_mode: :private,
            session_id: nil,
            attached?: false,
            streaming?: false,
            workspace: nil,
            workspace_mode: :chat,
            workspace_view: :files,
            open_file: nil,
            active_symbol_line: nil,
            file_scroll_line: nil,
            review: nil,
            active_review_comment_id: nil,
            palette: nil

  @type t :: %__MODULE__{
          connection_ref: term(),
          channel_id: term(),
          width: pos_integer(),
          height: pos_integer(),
          session: Session.t() | nil,
          index: Index.t() | nil,
          session_server: SessionServer.name() | nil,
          session_mode: :private | :shared,
          session_id: String.t() | nil,
          attached?: boolean(),
          streaming?: boolean(),
          workspace: Workspace.t() | nil,
          workspace_mode: :chat | :file | :workspace,
          workspace_view: :files | :symbols,
          open_file: Tilde.Core.FileBuffer.t() | nil,
          active_symbol_line: pos_integer() | nil,
          file_scroll_line: pos_integer() | nil,
          review: Review.t() | nil,
          active_review_comment_id: String.t() | nil,
          palette: Palette.t() | nil
        }

  @impl true
  def init(args) do
    opts = normalize_args(args)

    session_server = Keyword.get(opts, :session_server)
    session_mode = Keyword.get(opts, :session_mode, :private)

    session = Keyword.get_lazy(opts, :session, &Tilde.Demo.Live.demo_session/0)
    workspace = WorkspaceFiles.workspace(session)

    {:ok,
     %__MODULE__{
       width: Keyword.get(opts, :width, 100),
       height: Keyword.get(opts, :height, 30),
       session: session,
       index: Index.new(),
       session_server: session_server,
       session_mode: session_mode,
       session_id: session.id,
       workspace: workspace,
       review: WorkspaceReview.review(workspace, session),
       palette: Palette.new()
     }}
  end

  @impl true
  def handle_msg({:ssh_channel_up, channel_id, connection_ref}, state) do
    {:ok, %{state | channel_id: channel_id, connection_ref: connection_ref}}
  end

  def handle_msg({:tilde_session_updated, _session_id, %Session{} = session}, state) do
    old_session = state.session
    session = LocalPrompt.preserve(session, old_session)
    state = state |> Map.put(:session, session) |> refresh_workbench(session)

    state = if session == old_session, do: state, else: render_change(state, old_session)

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
    old_state = state
    old_session = state.session

    state
    |> apply_keys(Keys.decode_many(data))
    |> case do
      {:cont, state} ->
        state = render_state_change(state, old_state, old_session)
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

    state
    |> Map.merge(%{session: session, session_id: session.id, attached?: true})
    |> refresh_workbench(session)
  end

  defp route_session(%__MODULE__{} = state), do: show_index(state)

  defp session_server_for(session_id) do
    {:ok, _pid} = SessionRegistry.ensure_started()
    SessionRegistry.via(session_id)
  end

  defp attach_session(%__MODULE__{} = state, session_id, opts) do
    session_id = SessionRegistry.normalize_id(session_id)
    old_server = state.session_server
    server = session_server_for(session_id)

    if old_server && old_server != server do
      SessionServer.unsubscribe(old_server)
    end

    {:ok, _pid} =
      SessionServer.ensure_started(server,
        session:
          Tilde.Session.Loader.load_or_new(session_id,
            new: fn -> Tilde.Demo.Live.demo_session(id: session_id) end
          )
      )

    session =
      case Keyword.get(opts, :submit) do
        input when is_binary(input) ->
          SessionServer.append_event(server, Tilde.input_submitted(input))

        _other ->
          SessionServer.subscribe(server)
      end

    state =
      %{
        state
        | session_server: server,
          session: session,
          session_id: session_id,
          attached?: Keyword.get(opts, :attached?, true),
          streaming?: false
      }
      |> refresh_workbench(session)

    if Keyword.get(opts, :announce?, true),
      do: render_session_snapshot(state, Keyword.get(opts, :label, "attached session"))

    state
  end

  defp detach_session(%__MODULE__{} = state), do: show_index(state)

  defp show_index(%__MODULE__{} = state) do
    if state.session_server do
      SessionServer.unsubscribe(state.session_server)
    end

    %{
      state
      | session: nil,
        index: Index.new(),
        session_server: nil,
        session_id: nil,
        attached?: false,
        streaming?: false,
        workspace: nil,
        workspace_mode: :chat,
        workspace_view: :files,
        open_file: nil,
        active_symbol_line: nil,
        file_scroll_line: nil,
        review: nil,
        active_review_comment_id: nil,
        palette: nil
    }
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

  defp refresh_workbench(%__MODULE__{} = state, %Session{} = session) do
    workspace =
      session
      |> WorkspaceFiles.workspace()
      |> Workspace.preserve_navigation(state.workspace)

    open_file = refresh_open_file(workspace, state.open_file)

    %{
      state
      | workspace: workspace,
        open_file: open_file,
        review: WorkspaceReview.review(workspace, session),
        palette: Palette.refresh(state.palette || Palette.new(), workspace, open_file)
    }
  end

  defp refresh_open_file(%Workspace{} = workspace, %{path: path}) when is_binary(path) do
    WorkspaceFiles.open_file(workspace, path)
  end

  defp refresh_open_file(_workspace, _open_file), do: nil

  defp apply_keys(%__MODULE__{session_server: nil, index: %Index{}} = state, keys) do
    apply_index_keys(state, keys)
  end

  defp apply_keys(%__MODULE__{session_server: nil} = state, keys) do
    apply_local_keys(state, keys)
  end

  defp apply_keys(%__MODULE__{session_server: server} = state, keys) do
    Enum.reduce_while(keys, {:cont, state}, fn
      key, {:cont, %{palette: %Palette{open?: true}} = state} ->
        apply_palette_key(state, key)

      :enter, {:cont, state} ->
        cond do
          accept_suggestion_before_submit?(state.session) ->
            {:cont, session} = Controller.apply_key(state.session, :enter)
            {:cont, {:cont, %{state | session: session}}}

          state.session.input.value == "" ->
            apply_shortcut_key(state, "enter")

          true ->
            submit_or_command(server, state)
        end

      key, {:cont, state} ->
        case shortcut_key(state, key) do
          nil -> LocalPrompt.apply_key(state, key)
          key -> apply_shortcut_key(state, key)
        end
    end)
  end

  defp apply_palette_key(state, :palette_open), do: apply_shortcut_key(state, "ctrl+p")
  defp apply_palette_key(state, :cancel), do: apply_shortcut_key(state, "escape")
  defp apply_palette_key(state, :up), do: apply_shortcut_key(state, "arrowup")
  defp apply_palette_key(state, :down), do: apply_shortcut_key(state, "arrowdown")
  defp apply_palette_key(state, :enter), do: apply_shortcut_key(state, "enter")

  defp apply_palette_key(state, {:text, key}) when key in ["f", "s"],
    do: apply_shortcut_key(state, key)

  defp apply_palette_key(state, _key), do: {:cont, {:cont, state}}

  defp shortcut_key(_state, :palette_open), do: "ctrl+p"
  defp shortcut_key(%{workspace_mode: :file}, :redraw), do: "r"
  defp shortcut_key(%{workspace_mode: :file}, :cancel), do: "escape"
  defp shortcut_key(%{workspace_mode: :file}, :up), do: "arrowup"
  defp shortcut_key(%{workspace_mode: :file}, :down), do: "arrowdown"
  defp shortcut_key(%{workspace_mode: :file}, :page_up), do: "pageup"
  defp shortcut_key(%{workspace_mode: :file}, :page_down), do: "pagedown"
  defp shortcut_key(%{workspace_mode: :file}, {:text, "j"}), do: "j"
  defp shortcut_key(%{workspace_mode: :file}, {:text, "k"}), do: "k"

  defp shortcut_key(%{workspace_mode: :file}, {:text, key})
       when key in ["f", "s", "r", "x", "n", "p"],
       do: key

  defp shortcut_key(%{session: %Session{input: %{value: ""}}} = state, :cancel),
    do: if(state.workspace_mode == :workspace, do: "escape")

  defp shortcut_key(%{session: %Session{input: %{value: ""}}}, :up), do: "arrowup"
  defp shortcut_key(%{session: %Session{input: %{value: ""}}}, :down), do: "arrowdown"
  defp shortcut_key(%{session: %Session{input: %{value: ""}}}, {:text, "j"}), do: "j"
  defp shortcut_key(%{session: %Session{input: %{value: ""}}}, {:text, "k"}), do: "k"

  defp shortcut_key(%{session: %Session{input: %{value: ""}}}, {:text, key})
       when key in ["f", "s"],
       do: key

  defp shortcut_key(_state, _key), do: nil

  defp accept_suggestion_before_submit?(%Session{} = session) do
    case {Session.command_suggestions(session), SlashCommand.completion(session.input.value)} do
      {nil, _completion} ->
        false

      {_suggestions, completion} when completion in [nil, session.input.value] ->
        false

      {_suggestions, _completion} ->
        true
    end
  end

  defp apply_shortcut_key(%__MODULE__{} = state, key) do
    state
    |> shortcut_scope()
    |> Shortcuts.match(key)
    |> apply_shortcut_id(state)
  end

  defp shortcut_scope(%__MODULE__{palette: %Palette{open?: true}}), do: :palette
  defp shortcut_scope(%__MODULE__{workspace_mode: :file}), do: :buffer
  defp shortcut_scope(%__MODULE__{workspace_mode: :workspace}), do: :workspace
  defp shortcut_scope(%__MODULE__{}), do: :chat

  defp apply_shortcut_id(nil, state), do: {:cont, {:cont, state}}

  defp apply_shortcut_id("tilde.workspace.view_files", state) do
    {:cont, {:cont, %{state | workspace_view: :files, workspace_mode: :workspace}}}
  end

  defp apply_shortcut_id("tilde.workspace.view_symbols", state) do
    {:cont, {:cont, %{state | workspace_view: :symbols, workspace_mode: :workspace}}}
  end

  defp apply_shortcut_id("tilde.session.chat", state) do
    {:cont,
     {:cont,
      %{
        state
        | workspace_mode: :chat,
          open_file: nil,
          active_symbol_line: nil,
          file_scroll_line: nil
      }}}
  end

  defp apply_shortcut_id("tilde.review.focus", state), do: {:cont, {:cont, focus_review(state)}}

  defp apply_shortcut_id("tilde.review.toggle_current", state) do
    {:cont, {:cont, toggle_review_comment(state)}}
  end

  defp apply_shortcut_id("tilde.review.next", state),
    do: {:cont, {:cont, focus_adjacent_review(state, :next)}}

  defp apply_shortcut_id("tilde.review.previous", state),
    do: {:cont, {:cont, focus_adjacent_review(state, :previous)}}

  defp apply_shortcut_id("tilde.file.page_up", state),
    do: {:cont, {:cont, scroll_open_file(state, :up)}}

  defp apply_shortcut_id("tilde.file.page_down", state),
    do: {:cont, {:cont, scroll_open_file(state, :down)}}

  defp apply_shortcut_id("tilde.workspace.focus_previous", state) do
    {:cont, {:cont, focus_workspace_file(state, :previous)}}
  end

  defp apply_shortcut_id("tilde.workspace.focus_next", state) do
    {:cont, {:cont, focus_workspace_file(state, :next)}}
  end

  defp apply_shortcut_id("tilde.workspace.open_focused", state) do
    {:cont, {:cont, open_focused_workspace_file(state)}}
  end

  defp apply_shortcut_id("tilde.palette.open", state) do
    palette = Palette.open_files(state.workspace, (state.palette || Palette.new()).query)
    {:cont, {:cont, %{state | palette: palette}}}
  end

  defp apply_shortcut_id("tilde.palette.mode_files", state) do
    {:cont, {:cont, switch_palette_mode(state, :files)}}
  end

  defp apply_shortcut_id("tilde.palette.mode_symbols", state) do
    {:cont, {:cont, switch_palette_mode(state, :symbols)}}
  end

  defp apply_shortcut_id("tilde.palette.close", state) do
    {:cont, {:cont, %{state | palette: %{state.palette | open?: false}}}}
  end

  defp apply_shortcut_id("tilde.palette.previous", state) do
    {:cont, {:cont, %{state | palette: Palette.move(state.palette, :previous)}}}
  end

  defp apply_shortcut_id("tilde.palette.next", state) do
    {:cont, {:cont, %{state | palette: Palette.move(state.palette, :next)}}}
  end

  defp apply_shortcut_id("tilde.palette.accept", state) do
    {:cont, {:cont, accept_palette(state)}}
  end

  defp apply_shortcut_id(_shortcut, state), do: {:cont, {:cont, state}}

  defp switch_palette_mode(%__MODULE__{} = state, mode) do
    %{state | palette: Palette.switch_mode(state.palette, mode, state.workspace, state.open_file)}
  end

  defp accept_palette(%__MODULE__{palette: %Palette{} = palette} = state) do
    case Palette.selected_item(palette) do
      %{action: %{type: :open_file, path: path}} ->
        open_workspace_file(%{state | palette: palette}, path)

      %{action: %{type: :jump_symbol, line: line}} ->
        %{
          state
          | palette: %{palette | open?: false},
            workspace_mode: :file,
            workspace_view: :symbols,
            active_symbol_line: line,
            file_scroll_line: nil
        }

      _item ->
        state
    end
  end

  defp focus_review(%__MODULE__{review: %Review{} = review} = state) do
    review
    |> Review.focused_comment_id(state.active_review_comment_id)
    |> case do
      nil -> state
      comment_id -> jump_review_comment(state, comment_id)
    end
  end

  defp focus_review(%__MODULE__{} = state), do: state

  defp focus_adjacent_review(%__MODULE__{review: %Review{} = review} = state, direction) do
    review
    |> Review.adjacent_comment_id(state.active_review_comment_id, direction)
    |> case do
      nil -> state
      comment_id -> jump_review_comment(state, comment_id)
    end
  end

  defp focus_adjacent_review(%__MODULE__{} = state, _direction), do: state

  defp scroll_open_file(%__MODULE__{open_file: %{line_count: line_count}} = state, direction)
       when line_count > 0 do
    page_size = file_page_size(state)

    current_line =
      state.file_scroll_line || centered_start_line(state.active_symbol_line, page_size)

    next_line = scroll_line(current_line, line_count, page_size, direction)

    %{state | workspace_mode: :file, file_scroll_line: next_line}
  end

  defp scroll_open_file(%__MODULE__{} = state, _direction), do: state

  defp file_page_size(%__MODULE__{height: height}), do: max(height - 8, 1)

  defp centered_start_line(line, page_size) when is_integer(line) and line > 0,
    do: max(line - div(page_size, 2), 1)

  defp centered_start_line(_line, _page_size), do: 1

  defp scroll_line(current_line, line_count, page_size, :up) do
    max(current_line - page_size, 1)
    |> min(max_start_line(line_count, page_size))
  end

  defp scroll_line(current_line, line_count, page_size, :down) do
    min(current_line + page_size, max_start_line(line_count, page_size))
  end

  defp max_start_line(line_count, page_size), do: max(line_count - page_size + 1, 1)

  defp toggle_review_comment(%__MODULE__{review: %Review{} = review} = state) do
    case active_or_focused_review_comment_id(review, state.active_review_comment_id) do
      nil -> toggle_review_comment(state)
      comment_id -> toggle_review_comment(state, comment_id)
    end
  end

  defp toggle_review_comment(%__MODULE__{} = state), do: state

  defp active_or_focused_review_comment_id(%Review{} = review, active_comment_id) do
    if is_binary(active_comment_id) and Review.find_comment(review, active_comment_id) do
      active_comment_id
    else
      Review.focused_comment_id(review, active_comment_id)
    end
  end

  defp toggle_review_comment(%__MODULE__{review: %Review{} = review} = state, comment_id) do
    case Review.find_comment(review, comment_id) do
      %{status: :open} ->
        persist_review(state, Review.resolve_comment(review, comment_id), comment_id)

      %{status: :resolved} ->
        persist_review(state, Review.reopen_comment(review, comment_id), comment_id)

      _comment ->
        state
    end
  end

  defp persist_review(%__MODULE__{session_server: server} = state, %Review{} = review, comment_id)
       when not is_nil(server) do
    session = SessionServer.update_session(server, &ReviewState.put(&1, review))

    %{
      state
      | session: session,
        review: ReviewState.load(review, session),
        active_review_comment_id: comment_id
    }
  end

  defp persist_review(%__MODULE__{} = state, %Review{} = review, comment_id) do
    %{state | review: review, active_review_comment_id: comment_id}
  end

  defp jump_review_comment(%__MODULE__{review: %Review{} = review} = state, comment_id) do
    case Review.find_comment(review, comment_id) do
      %{path: path, line: line, id: id} -> open_workspace_file_at_line(state, path, line, id)
      nil -> state
    end
  end

  defp open_workspace_file_at_line(state, path, line, comment_id) do
    state
    |> open_workspace_file(path)
    |> Map.merge(%{
      workspace_view: :files,
      active_symbol_line: line,
      file_scroll_line: nil,
      active_review_comment_id: comment_id
    })
  end

  defp open_workspace_file(%__MODULE__{workspace: %Workspace{} = workspace} = state, path) do
    workspace = %{workspace | selected_path: path, focused_path: path}

    %{
      state
      | workspace: workspace,
        palette: %{state.palette | open?: false},
        workspace_mode: :file,
        workspace_view: :symbols,
        open_file: WorkspaceFiles.open_file(workspace, path),
        active_symbol_line: nil,
        file_scroll_line: 1,
        active_review_comment_id: nil
    }
  end

  defp focus_workspace_file(%__MODULE__{workspace: %Workspace{} = workspace} = state, direction) do
    focused_workspace = Workspace.focus_file(workspace, direction)

    if focused_workspace == workspace do
      state
    else
      %{state | workspace: focused_workspace, workspace_mode: :workspace}
    end
  end

  defp focus_workspace_file(%__MODULE__{} = state, _direction), do: state

  defp open_focused_workspace_file(%__MODULE__{workspace: %Workspace{} = workspace} = state) do
    focused_path = workspace.focused_path

    if focused_path in Workspace.visible_file_paths(workspace) do
      open_workspace_file(state, focused_path)
    else
      state
    end
  end

  defp open_focused_workspace_file(%__MODULE__{} = state), do: state

  defp submit_or_command(server, state) do
    case transport_effects(state.session.input.value, state.session) do
      [] ->
        LocalPrompt.submit(server, state)

      outcomes ->
        {:cont, {:cont, apply_outcomes(state, outcomes)}}
    end
  end

  defp transport_effects(input, %Session{} = session) do
    case SlashCommand.parse(input) do
      {:ok, command} ->
        command |> SlashCommand.run(session, []) |> Outcome.from_command_effects()

      :error ->
        []
    end
  end

  defp apply_index_keys(%__MODULE__{} = state, keys) do
    Enum.reduce_while(keys, {:cont, state}, fn key, {:cont, state} ->
      case SSHInteraction.index(state.index, key) do
        :halt ->
          {:halt, {:halt, state}}

        nil ->
          {:cont, {:cont, state}}

        %Interaction{} = interaction ->
          {:cont, {:cont, apply_index_interaction(state, interaction)}}
      end
    end)
  end

  defp apply_index_interaction(%__MODULE__{} = state, %Interaction{} = interaction) do
    {:cont, index, effects} = Index.apply_interaction(state.index, interaction)

    state
    |> Map.put(:index, index)
    |> apply_index_effects(effects)
  end

  defp apply_index_effects(%__MODULE__{} = state, outcomes), do: apply_outcomes(state, outcomes)

  defp apply_outcomes(%__MODULE__{} = state, outcomes) do
    SSHOutcome.apply(state, outcomes,
      attach: fn state, id, payload -> attach_session(state, id, Map.to_list(payload)) end,
      detach: &detach_session/1,
      show_session_info: &show_session_info/1
    )
  end

  defp apply_local_keys(%__MODULE__{} = state, keys) do
    Enum.reduce_while(keys, {:cont, state}, fn key, {:cont, state} ->
      case Controller.apply_key(state.session, key) do
        {:cont, session} -> {:cont, {:cont, %{state | session: session}}}
        {:halt, session} -> {:halt, {:halt, %{state | session: session}}}
      end
    end)
  end

  defp render_state_change(%__MODULE__{} = state, %__MODULE__{} = old_state, old_session) do
    cond do
      state.session == old_session and state != old_state ->
        render(state)
        state

      prompt_changed?(state.session, old_session) ->
        render(state)
        state

      true ->
        render_change(state, old_session)
    end
  end

  defp prompt_changed?(%Session{input: input}, %Session{input: input}), do: false
  defp prompt_changed?(%Session{}, %Session{}), do: true
  defp prompt_changed?(_session, _old_session), do: false

  defp render_change(%__MODULE__{session: nil} = state, _old_session) do
    render(state)
    state
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

  defp render(%__MODULE__{index: %Index{}, session_server: nil} = state) do
    send_bytes(state, Rendering.index(state.index, state.width))
  end

  defp render(%__MODULE__{} = state) do
    send_bytes(state, Rendering.workbench(state, state.width, state.height))
  end

  defp render_session_snapshot(%__MODULE__{} = state, label) do
    send_bytes(
      state,
      Rendering.session_snapshot(
        state.session,
        state.session_id,
        label,
        state.width,
        state.height
      )
    )
  end

  defp render_session_info(%__MODULE__{} = state) do
    send_bytes(state, Rendering.session_info(state.session, state.session_id, state.attached?))
  end

  defp render_input_change(%__MODULE__{} = state, %Session{} = old_session) do
    send_bytes(
      state,
      Rendering.input_change(old_session.input, state.session.input, state.session)
    )
  end

  defp append_blocks(%__MODULE__{} = state, blocks, opts) do
    send_bytes(state, Rendering.blocks(blocks, state.session, state.width, opts))
  end

  defp append_text(%__MODULE__{} = state, text) do
    send_bytes(state, Rendering.text(text))
  end

  defp append_tool_delta(%__MODULE__{} = state, kind, text, first?) do
    send_bytes(state, Rendering.tool_delta(kind, text, first?))
  end

  defp append_prompt(%__MODULE__{} = state) do
    send_bytes(state, Rendering.prompt_after_turn(state.session))
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
