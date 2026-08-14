defmodule Tilde.Workbench do
  @moduledoc """
  Transport-neutral state and orchestration for a session workbench.

  LiveView and SSH translate their native events into workbench actions, apply
  returned state, and interpret effects such as durable review updates.
  """

  alias Tilde.Core.{Palette, Review, Session, Shortcuts, Workspace}
  alias Tilde.Runtime.{WorkspaceFiles, WorkspaceReview}

  defstruct session: nil,
            workspace: nil,
            workspace_mode: :chat,
            workspace_view: :files,
            open_file: nil,
            active_symbol_line: nil,
            file_scroll_line: nil,
            review: nil,
            review_open?: true,
            active_review_comment_id: nil,
            palette: nil

  @type mode :: :chat | :file | :workspace
  @type view :: :files | :symbols
  @type effect :: {:persist_review, Review.t()}

  @type t :: %__MODULE__{
          session: Session.t() | nil,
          workspace: Workspace.t() | nil,
          workspace_mode: mode(),
          workspace_view: view(),
          open_file: Tilde.Core.FileBuffer.t() | nil,
          active_symbol_line: pos_integer() | nil,
          file_scroll_line: pos_integer() | nil,
          review: Review.t() | nil,
          review_open?: boolean(),
          active_review_comment_id: String.t() | nil,
          palette: Palette.t() | nil
        }

  @type action ::
          :show_chat
          | :focus_review
          | :toggle_review_comment
          | :accept_palette
          | {:show_workspace, view()}
          | {:set_workspace_view, view()}
          | {:open_file, String.t()}
          | {:jump_symbol, pos_integer() | nil}
          | {:jump_review_comment, String.t()}
          | {:focus_review, :next | :previous}
          | {:set_review_status, String.t(), :open | :resolved}
          | {:query_palette, String.t()}
          | {:switch_palette_mode, Palette.mode() | String.t()}
          | {:select_palette, non_neg_integer() | String.t()}
          | {:scroll_file, :up | :down}
          | {:shortcut, String.t()}

  @fields [
    :session,
    :workspace,
    :workspace_mode,
    :workspace_view,
    :open_file,
    :active_symbol_line,
    :file_scroll_line,
    :review,
    :review_open?,
    :active_review_comment_id,
    :palette
  ]

  @doc "Builds workbench state for a semantic session."
  @spec new(Session.t(), keyword()) :: t()
  def new(%Session{} = session, opts \\ []) do
    %__MODULE__{
      workspace_mode: Keyword.get(opts, :workspace_mode, :chat),
      workspace_view: Keyword.get(opts, :workspace_view, :files),
      review_open?: Keyword.get(opts, :review_open?, true),
      palette: Palette.new()
    }
    |> refresh(session)
  end

  @doc "Projects workbench fields from an adapter state or LiveView assigns map."
  @spec from_map(map()) :: t()
  def from_map(%__MODULE__{} = workbench), do: workbench

  def from_map(state) when is_map(state) do
    struct(__MODULE__, Map.take(state, @fields))
  end

  @doc "Returns workbench fields suitable for merging into adapter state."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = workbench), do: Map.from_struct(workbench)

  @doc "Refreshes workspace-derived state while preserving navigation."
  @spec refresh(t(), Session.t()) :: t()
  def refresh(%__MODULE__{} = workbench, %Session{} = session) do
    workspace =
      session
      |> WorkspaceFiles.workspace()
      |> Workspace.preserve_navigation(workbench.workspace)

    open_file = refresh_open_file(workspace, workbench.open_file)

    %{
      workbench
      | session: session,
        workspace: workspace,
        open_file: open_file,
        review: WorkspaceReview.review(workspace, session),
        palette: Palette.refresh(workbench.palette || Palette.new(), workspace, open_file)
    }
  end

  @doc "Returns the active shortcut scope for this workbench."
  @spec shortcut_scope(t()) :: :palette | :buffer | :workspace | :chat
  def shortcut_scope(%__MODULE__{palette: %Palette{open?: true}}), do: :palette
  def shortcut_scope(%__MODULE__{workspace_mode: :file}), do: :buffer
  def shortcut_scope(%__MODULE__{workspace_mode: :workspace}), do: :workspace
  def shortcut_scope(%__MODULE__{}), do: :chat

  @doc "Reduces a workbench action and returns state plus adapter effects."
  @spec apply_action(t(), action(), keyword()) :: {t(), [effect()]}
  def apply_action(workbench, action, opts \\ [])

  def apply_action(workbench, :show_chat, _opts) do
    {%{
       workbench
       | workspace_mode: :chat,
         open_file: nil,
         active_symbol_line: nil,
         file_scroll_line: nil
     }, []}
  end

  def apply_action(workbench, {:show_workspace, view}, _opts) when view in [:files, :symbols] do
    {%{workbench | workspace_mode: :workspace, workspace_view: view}, []}
  end

  def apply_action(workbench, {:set_workspace_view, view}, _opts)
      when view in [:files, :symbols] do
    {%{workbench | workspace_view: view}, []}
  end

  def apply_action(workbench, {:open_file, path}, _opts) when is_binary(path) do
    {open_workspace_file(workbench, path), []}
  end

  def apply_action(workbench, {:jump_symbol, line}, _opts) do
    {%{
       workbench
       | workspace_mode: :file,
         workspace_view: :symbols,
         active_symbol_line: normalize_line(line),
         file_scroll_line: nil
     }, []}
  end

  def apply_action(workbench, {:jump_review_comment, comment_id}, _opts)
      when is_binary(comment_id) do
    {jump_review_comment(workbench, comment_id), []}
  end

  def apply_action(workbench, :focus_review, _opts) do
    {focus_review(workbench, :current), []}
  end

  def apply_action(workbench, {:focus_review, direction}, _opts)
      when direction in [:next, :previous] do
    {focus_review(workbench, direction), []}
  end

  def apply_action(workbench, {:set_review_status, comment_id, status}, _opts)
      when is_binary(comment_id) and status in [:open, :resolved] do
    update_review_status(workbench, comment_id, status)
  end

  def apply_action(workbench, :toggle_review_comment, _opts) do
    toggle_review_comment(workbench)
  end

  def apply_action(
        %__MODULE__{palette: %Palette{} = palette} = workbench,
        {:query_palette, query},
        _opts
      )
      when is_binary(query) do
    palette = Palette.query(palette, workbench.workspace, workbench.open_file, query)
    {%{workbench | palette: palette}, []}
  end

  def apply_action(
        %__MODULE__{palette: %Palette{} = palette} = workbench,
        {:switch_palette_mode, mode},
        _opts
      ) do
    palette = Palette.switch_mode(palette, mode, workbench.workspace, workbench.open_file)
    {%{workbench | palette: palette}, []}
  end

  def apply_action(
        %__MODULE__{palette: %Palette{} = palette} = workbench,
        {:select_palette, index},
        _opts
      ) do
    {%{workbench | palette: select_palette_index(palette, index)}, []}
  end

  def apply_action(workbench, :accept_palette, _opts), do: {accept_palette(workbench), []}

  def apply_action(workbench, {:scroll_file, direction}, opts) when direction in [:up, :down] do
    {scroll_open_file(workbench, direction, opts), []}
  end

  def apply_action(workbench, {:shortcut, key}, opts) when is_binary(key) do
    shortcut = workbench |> shortcut_scope() |> Shortcuts.match(key)
    apply_shortcut(workbench, shortcut, opts)
  end

  def apply_action(workbench, _action, _opts), do: {workbench, []}

  defp apply_shortcut(workbench, "tilde.workspace.view_files", _opts),
    do: apply_action(workbench, {:show_workspace, :files})

  defp apply_shortcut(workbench, "tilde.workspace.view_symbols", _opts),
    do: apply_action(workbench, {:show_workspace, :symbols})

  defp apply_shortcut(workbench, "tilde.session.chat", _opts),
    do: apply_action(workbench, :show_chat)

  defp apply_shortcut(workbench, "tilde.review.focus", _opts),
    do: apply_action(workbench, :focus_review)

  defp apply_shortcut(workbench, "tilde.review.toggle_current", _opts),
    do: apply_action(workbench, :toggle_review_comment)

  defp apply_shortcut(workbench, "tilde.review.next", _opts),
    do: apply_action(workbench, {:focus_review, :next})

  defp apply_shortcut(workbench, "tilde.review.previous", _opts),
    do: apply_action(workbench, {:focus_review, :previous})

  defp apply_shortcut(workbench, "tilde.file.page_up", opts),
    do: apply_action(workbench, {:scroll_file, :up}, opts)

  defp apply_shortcut(workbench, "tilde.file.page_down", opts),
    do: apply_action(workbench, {:scroll_file, :down}, opts)

  defp apply_shortcut(workbench, "tilde.workspace.focus_previous", _opts),
    do: {focus_workspace_file(workbench, :previous), []}

  defp apply_shortcut(workbench, "tilde.workspace.focus_next", _opts),
    do: {focus_workspace_file(workbench, :next), []}

  defp apply_shortcut(workbench, "tilde.workspace.open_focused", _opts),
    do: {open_focused_workspace_file(workbench), []}

  defp apply_shortcut(workbench, "tilde.palette.open", _opts),
    do: {open_palette(workbench), []}

  defp apply_shortcut(workbench, "tilde.palette.mode_files", _opts),
    do: apply_action(workbench, {:switch_palette_mode, :files})

  defp apply_shortcut(workbench, "tilde.palette.mode_symbols", _opts),
    do: apply_action(workbench, {:switch_palette_mode, :symbols})

  defp apply_shortcut(workbench, "tilde.palette.close", _opts),
    do: {close_palette(workbench), []}

  defp apply_shortcut(
         %__MODULE__{palette: %Palette{} = palette} = workbench,
         "tilde.palette.previous",
         _opts
       ),
       do: {%{workbench | palette: Palette.move(palette, :previous)}, []}

  defp apply_shortcut(
         %__MODULE__{palette: %Palette{} = palette} = workbench,
         "tilde.palette.next",
         _opts
       ),
       do: {%{workbench | palette: Palette.move(palette, :next)}, []}

  defp apply_shortcut(workbench, "tilde.palette.accept", _opts),
    do: apply_action(workbench, :accept_palette)

  defp apply_shortcut(workbench, _shortcut, _opts), do: {workbench, []}

  defp open_palette(%__MODULE__{workspace: %Workspace{} = workspace} = workbench) do
    query = (workbench.palette || Palette.new()).query
    %{workbench | palette: Palette.open_files(workspace, query)}
  end

  defp open_palette(workbench), do: workbench

  defp close_palette(%__MODULE__{palette: %Palette{} = palette} = workbench),
    do: %{workbench | palette: %{palette | open?: false}}

  defp close_palette(workbench), do: workbench

  defp accept_palette(%__MODULE__{palette: %Palette{} = palette} = workbench) do
    case Palette.selected_item(palette) do
      %{action: %{type: :open_file, path: path}} ->
        open_workspace_file(workbench, path)

      %{action: %{type: :jump_symbol, line: line}} ->
        %{
          workbench
          | palette: %{palette | open?: false},
            workspace_mode: :file,
            workspace_view: :symbols,
            active_symbol_line: line,
            file_scroll_line: nil
        }

      _item ->
        workbench
    end
  end

  defp accept_palette(workbench), do: workbench

  defp select_palette_index(palette, index) when is_integer(index),
    do: %{palette | selected_index: max(index, 0)}

  defp select_palette_index(palette, index) when is_binary(index) do
    case Integer.parse(index) do
      {index, ""} -> select_palette_index(palette, index)
      _other -> palette
    end
  end

  defp select_palette_index(palette, _index), do: palette

  defp open_workspace_file(
         %__MODULE__{workspace: %Workspace{} = workspace} = workbench,
         path
       ) do
    workspace = %{workspace | selected_path: path, focused_path: path}

    %{
      workbench
      | workspace: workspace,
        palette: close_palette_state(workbench.palette),
        workspace_mode: :file,
        workspace_view: :symbols,
        open_file: WorkspaceFiles.open_file(workspace, path),
        active_symbol_line: nil,
        file_scroll_line: 1,
        active_review_comment_id: nil
    }
  end

  defp open_workspace_file(workbench, _path), do: workbench

  defp jump_review_comment(%__MODULE__{review: %Review{} = review} = workbench, comment_id) do
    case Review.find_comment(review, comment_id) do
      %{path: path, line: line, id: id} ->
        workbench
        |> open_workspace_file(path)
        |> Map.merge(%{
          workspace_view: :files,
          active_symbol_line: line,
          file_scroll_line: nil,
          active_review_comment_id: id,
          review_open?: true
        })

      nil ->
        workbench
    end
  end

  defp jump_review_comment(workbench, _comment_id), do: workbench

  defp focus_review(%__MODULE__{review: %Review{} = review} = workbench, direction) do
    comment_id =
      case direction do
        :current ->
          Review.focused_comment_id(review, workbench.active_review_comment_id)

        direction ->
          Review.adjacent_comment_id(review, workbench.active_review_comment_id, direction)
      end

    workbench = %{workbench | review_open?: true}
    if comment_id, do: jump_review_comment(workbench, comment_id), else: workbench
  end

  defp focus_review(workbench, _direction), do: %{workbench | review_open?: true}

  defp update_review_status(%__MODULE__{review: %Review{} = review} = workbench, id, status) do
    case Review.find_comment(review, id) do
      nil ->
        {workbench, []}

      _comment ->
        review =
          case status do
            :resolved -> Review.resolve_comment(review, id)
            :open -> Review.reopen_comment(review, id)
          end

        {%{workbench | review: review, active_review_comment_id: id}, [{:persist_review, review}]}
    end
  end

  defp update_review_status(workbench, _id, _status), do: {workbench, []}

  defp toggle_review_comment(%__MODULE__{review: %Review{} = review} = workbench) do
    id = active_or_focused_review_comment_id(review, workbench.active_review_comment_id)

    case Review.find_comment(review, id || "") do
      %{status: :open} -> update_review_status(workbench, id, :resolved)
      %{status: :resolved} -> update_review_status(workbench, id, :open)
      _comment -> {workbench, []}
    end
  end

  defp toggle_review_comment(workbench), do: {workbench, []}

  defp active_or_focused_review_comment_id(review, active_comment_id) do
    if is_binary(active_comment_id) and Review.find_comment(review, active_comment_id) do
      active_comment_id
    else
      Review.focused_comment_id(review, active_comment_id)
    end
  end

  defp focus_workspace_file(
         %__MODULE__{workspace: %Workspace{} = workspace} = workbench,
         direction
       ) do
    focused_workspace = Workspace.focus_file(workspace, direction)

    if focused_workspace == workspace do
      workbench
    else
      %{workbench | workspace: focused_workspace, workspace_mode: :workspace}
    end
  end

  defp focus_workspace_file(workbench, _direction), do: workbench

  defp open_focused_workspace_file(%__MODULE__{workspace: %Workspace{} = workspace} = workbench) do
    if workspace.focused_path in Workspace.visible_file_paths(workspace) do
      open_workspace_file(workbench, workspace.focused_path)
    else
      workbench
    end
  end

  defp open_focused_workspace_file(workbench), do: workbench

  defp scroll_open_file(
         %__MODULE__{open_file: %{line_count: line_count}} = workbench,
         direction,
         opts
       )
       when line_count > 0 do
    page_size = max(Keyword.get(opts, :page_size, 20), 1)
    field = Keyword.get(opts, :scroll_field, :file_scroll_line)
    current_line = scroll_start_line(workbench, field, page_size)
    next_line = scroll_line(current_line, line_count, page_size, direction)

    workbench
    |> Map.put(:workspace_mode, :file)
    |> Map.put(field, next_line)
  end

  defp scroll_open_file(workbench, _direction, _opts), do: workbench

  defp scroll_start_line(workbench, :active_symbol_line, _page_size),
    do: workbench.active_symbol_line || 1

  defp scroll_start_line(workbench, :file_scroll_line, page_size) do
    workbench.file_scroll_line || centered_start_line(workbench.active_symbol_line, page_size)
  end

  defp centered_start_line(line, page_size) when is_integer(line) and line > 0,
    do: max(line - div(page_size, 2), 1)

  defp centered_start_line(_line, _page_size), do: 1

  defp scroll_line(current_line, line_count, page_size, :up),
    do: min(max(current_line - page_size, 1), max_start_line(line_count, page_size))

  defp scroll_line(current_line, line_count, page_size, :down),
    do: min(current_line + page_size, max_start_line(line_count, page_size))

  defp max_start_line(line_count, page_size), do: max(line_count - page_size + 1, 1)

  defp refresh_open_file(%Workspace{} = workspace, %{path: path}) when is_binary(path),
    do: WorkspaceFiles.open_file(workspace, path)

  defp refresh_open_file(_workspace, _open_file), do: nil

  defp close_palette_state(%Palette{} = palette), do: %{palette | open?: false}
  defp close_palette_state(_palette), do: Palette.new()

  defp normalize_line(line) when is_integer(line) and line > 0, do: line

  defp normalize_line(line) when is_binary(line) do
    case Integer.parse(line) do
      {line, ""} when line > 0 -> line
      _other -> nil
    end
  end

  defp normalize_line(_line), do: nil
end
