defmodule Tilde.Core.Review.Comment do
  @moduledoc """
  Renderer-neutral review comment anchored to a workspace file and line range.
  """

  defstruct id: "",
            path: "",
            line: 1,
            end_line: nil,
            severity: :note,
            body: "",
            status: :open

  @type severity :: :note | :warning | :issue
  @type status :: :open | :resolved

  @type t :: %__MODULE__{
          id: String.t(),
          path: String.t(),
          line: pos_integer(),
          end_line: pos_integer() | nil,
          severity: severity(),
          body: String.t(),
          status: status()
        }

  @doc "Builds a review comment."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      path: Keyword.fetch!(opts, :path),
      line: Keyword.get(opts, :line, 1),
      end_line: Keyword.get(opts, :end_line),
      severity: Keyword.get(opts, :severity, :note),
      body: Keyword.fetch!(opts, :body),
      status: Keyword.get(opts, :status, :open)
    }
  end
end
