defmodule Tilde.Core.Review do
  @moduledoc """
  Renderer-neutral code review state.

  A review is session/workspace data. Renderers decide whether it appears in a
  right pane, TUI panel, transcript export, or another surface.
  """

  alias Tilde.Core.Review.Comment
  alias Tilde.Core.Review.File

  defstruct id: "", title: "", status: :open, files: []

  @type status :: :open | :complete

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          status: status(),
          files: [File.t()]
        }

  @doc "Builds review state."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, "review"),
      title: Keyword.get(opts, :title, "review"),
      status: Keyword.get(opts, :status, :open),
      files: Keyword.get(opts, :files, [])
    }
  end

  @doc "Returns all comments in file order."
  @spec comments(t()) :: [Comment.t()]
  def comments(%__MODULE__{files: files}) do
    Enum.flat_map(files, & &1.comments)
  end

  @doc "Returns open comment count."
  @spec open_comment_count(t()) :: non_neg_integer()
  def open_comment_count(%__MODULE__{} = review) do
    review
    |> comments()
    |> Enum.count(&(&1.status == :open))
  end

  @doc "Marks a comment resolved."
  @spec resolve_comment(t(), String.t()) :: t()
  def resolve_comment(%__MODULE__{} = review, id) when is_binary(id) do
    update_comment_status(review, id, :resolved)
  end

  @doc "Reopens a resolved comment."
  @spec reopen_comment(t(), String.t()) :: t()
  def reopen_comment(%__MODULE__{} = review, id) when is_binary(id) do
    update_comment_status(review, id, :open)
  end

  @doc "Dumps comment statuses into a metadata-safe map."
  @spec dump_statuses(t()) :: %{String.t() => String.t()}
  def dump_statuses(%__MODULE__{} = review) do
    review
    |> comments()
    |> Map.new(fn %Comment{id: id, status: status} -> {id, Atom.to_string(status)} end)
  end

  @doc "Applies metadata-safe comment statuses to matching review comments."
  @spec apply_statuses(t(), map() | nil) :: t()
  def apply_statuses(%__MODULE__{} = review, statuses) when is_map(statuses) do
    Enum.reduce(statuses, review, fn {id, status}, review ->
      case normalize_comment_status(status) do
        nil -> review
        status -> update_comment_status(review, to_string(id), status)
      end
    end)
  end

  def apply_statuses(%__MODULE__{} = review, _statuses), do: review

  @doc "Finds a comment by id."
  @spec find_comment(t(), String.t()) :: Comment.t() | nil
  def find_comment(%__MODULE__{} = review, id) when is_binary(id) do
    Enum.find(comments(review), &(&1.id == id))
  end

  @doc "Returns review file entries that have at least one comment for the path."
  @spec file_comments(t(), String.t() | nil) :: [Comment.t()]
  def file_comments(_review, nil), do: []

  def file_comments(%__MODULE__{} = review, path) when is_binary(path) do
    review
    |> comments()
    |> Enum.filter(&(&1.path == path))
  end

  @doc "Returns review files other than the current path that have comments."
  @spec other_files(t(), String.t() | nil) :: [File.t()]
  def other_files(%__MODULE__{files: files}, current_path) do
    Enum.reject(files, fn %File{path: path, comments: comments} ->
      path == current_path or comments == []
    end)
  end

  @doc "Returns the active open comment id, falling back to the first open or any comment."
  @spec focused_comment_id(t(), String.t() | nil) :: String.t() | nil
  def focused_comment_id(%__MODULE__{} = review, active_comment_id) do
    with id when is_binary(id) <- active_comment_id,
         %{status: :open} <- find_comment(review, id) do
      id
    else
      _other -> first_comment_id(review, :open) || first_comment_id(review, :any)
    end
  end

  defp first_comment_id(%__MODULE__{} = review, status) do
    review
    |> comments()
    |> Enum.find(&comment_status?(&1, status))
    |> case do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp comment_status?(_comment, :any), do: true
  defp comment_status?(comment, status), do: comment.status == status

  defp normalize_comment_status(status) when status in [:open, :resolved], do: status
  defp normalize_comment_status("open"), do: :open
  defp normalize_comment_status("resolved"), do: :resolved
  defp normalize_comment_status(_status), do: nil

  defp update_comment_status(%__MODULE__{files: files} = review, id, status) do
    files =
      Enum.map(files, fn %File{comments: comments} = file ->
        comments =
          Enum.map(comments, fn
            %Comment{id: ^id} = comment -> %{comment | status: status}
            %Comment{} = comment -> comment
          end)

        %{file | comments: comments}
      end)

    %{review | files: files}
  end
end
