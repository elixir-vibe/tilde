defmodule Tilde.Renderer.TUI.Review do
  @moduledoc "Terminal renderer for the shared review state."

  alias Tilde.Core.Review
  alias Tilde.Core.Review.Comment
  alias Tilde.Core.Review.File, as: ReviewFile
  alias Tilde.Renderer.TUI.Theme

  @doc "Renders a review summary and comments for the current file."
  @spec render(Review.t() | nil, String.t() | nil, String.t() | nil, pos_integer(), keyword()) ::
          String.t()
  def render(review, current_path, active_comment_id, width, opts \\ [])

  def render(nil, _current_path, _active_comment_id, _width, opts),
    do: Theme.muted("No review.", opts)

  def render(%Review{} = review, current_path, active_comment_id, width, opts) do
    current_comments = Review.file_comments(review, current_path)
    other_files = Review.other_files(review, current_path)

    [
      header(review, opts),
      current_section(current_path, current_comments, active_comment_id, width, opts),
      other_files_section(other_files, width, opts)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp header(%Review{} = review, opts) do
    Theme.title("review", opts) <>
      " " <>
      Theme.muted("#{Review.open_comment_count(review)} open · #{review.title}", opts)
  end

  defp current_section(nil, _comments, _active_comment_id, _width, opts) do
    Theme.muted("current file: none", opts)
  end

  defp current_section(path, [], _active_comment_id, _width, opts) do
    [Theme.muted("current file", opts), path, Theme.muted("No comments for this file.", opts)]
    |> Enum.join("\n")
  end

  defp current_section(path, comments, active_comment_id, width, opts) do
    lines =
      Enum.map_join(comments, "\n", &comment_line(&1, &1.id == active_comment_id, width, opts))

    [Theme.muted("current file", opts), path, lines]
    |> Enum.join("\n")
  end

  defp other_files_section([], _width, _opts), do: ""

  defp other_files_section(files, width, opts) do
    rows =
      Enum.map_join(files, "\n", fn %ReviewFile{} = file ->
        count = length(file.comments)
        "  " <> truncate(file.path, max(width - 8, 12)) <> Theme.muted("  #{count}", opts)
      end)

    [Theme.muted("other files", opts), rows]
    |> Enum.join("\n")
  end

  defp comment_line(%Comment{} = comment, active?, width, opts) do
    marker = if active?, do: "›", else: " "
    meta = "#{comment.status} #{comment.severity} line #{comment.line}"
    body = truncate(comment.body, max(width - String.length(meta) - 5, 12))

    marker <> " " <> Theme.muted(meta, opts) <> " " <> body
  end

  defp truncate(text, width) do
    if String.length(text) <= width do
      text
    else
      String.slice(text, 0, max(width - 1, 0)) <> "…"
    end
  end
end
