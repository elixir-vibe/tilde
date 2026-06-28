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
