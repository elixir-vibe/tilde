defmodule Tilde.Transport.Live.Review do
  @moduledoc "LiveView components for Tilde's persistent review pane."

  use Phoenix.Component

  import Tilde.Transport.Live.Controls

  alias Tilde.Core.Review
  alias Tilde.Core.Review.Comment
  alias Tilde.Core.Review.File, as: ReviewFile

  attr(:review, Review, required: true)
  attr(:current_path, :string, default: nil)
  attr(:active_comment_id, :string, default: nil)

  def review_pane(assigns) do
    assigns =
      assigns
      |> assign(:current_comments, Review.file_comments(assigns.review, assigns.current_path))
      |> assign(:other_files, other_files(assigns.review, assigns.current_path))

    ~H"""
    <aside class="review" aria-label="review comments">
      <header class="header">
        <span class="title">review</span>
        <span class="meta">{Review.open_comment_count(@review)} open</span>
      </header>

      <div class="sections">
        <section class="section summary" aria-label="review summary">
          <header class="section_header">
            <span>{@review.title}</span>
            <span>{length(Review.comments(@review))}</span>
          </header>
        </section>

        <section class="section" aria-label="current file review">
          <header class="section_header">
            <span>current file</span>
            <span>{length(@current_comments)}</span>
          </header>
          <div :if={@current_path} class="path" title={@current_path}>{@current_path}</div>
          <div :if={@current_comments == []} class="empty">
            No comments for this file.
            <span>Open a reviewed file or select a comment below.</span>
          </div>
          <div :if={@current_comments != []} class="comments" role="list">
            <.comment_button
              :for={comment <- @current_comments}
              comment={comment}
              active?={comment.id == @active_comment_id}
            />
          </div>
        </section>

        <section :if={@other_files != []} class="section" aria-label="other reviewed files">
          <header class="section_header">
            <span>other files</span>
            <span>{length(@other_files)}</span>
          </header>
          <div class="files" role="list">
            <div :for={file <- @other_files} class="file" role="listitem">
              <button
                type="button"
                class="path"
                title={file.path}
                phx-click="tilde:review:jump_comment"
                phx-value-comment-id={List.first(file.comments).id}
              >
                {file.path}
              </button>
              <span class="meta">{length(file.comments)}</span>
            </div>
          </div>
        </section>
      </div>
    </aside>
    """
  end

  attr(:comment, Comment, required: true)
  attr(:active?, :boolean, default: false)

  defp comment_button(assigns) do
    ~H"""
    <div
      class={["comment", @comment.severity, @comment.status, @active? && "selected"]}
      role="listitem"
      title={comment_title(@comment)}
    >
      <button
        type="button"
        class="target"
        phx-click="tilde:review:jump_comment"
        phx-value-comment-id={@comment.id}
      >
        <span class="meta">{comment_meta(@comment)}</span>
        <span class="body">{@comment.body}</span>
      </button>
      <div class="actions" aria-label="review comment actions">
        <.action
          :if={@comment.status == :open}
          event="tilde:review:resolve_comment"
          label="resolve"
          values={%{"phx-value-comment-id" => @comment.id}}
        />
        <.action
          :if={@comment.status == :resolved}
          event="tilde:review:reopen_comment"
          label="reopen"
          values={%{"phx-value-comment-id" => @comment.id}}
        />
      </div>
    </div>
    """
  end

  defp other_files(%Review{files: files}, current_path) do
    Enum.reject(files, fn %ReviewFile{path: path, comments: comments} ->
      path == current_path or comments == []
    end)
  end

  defp comment_title(%Comment{} = comment) do
    [comment.path, "line #{comment.line}", severity_label(comment), status_label(comment)]
    |> Enum.join(" · ")
  end

  defp comment_meta(%Comment{} = comment) do
    [status_label(comment), severity_label(comment), "line #{comment.line}"]
    |> Enum.reject(&(&1 == "open"))
    |> Enum.join(" ")
  end

  defp severity_label(%Comment{severity: severity}), do: to_string(severity)
  defp status_label(%Comment{status: status}), do: to_string(status)
end
