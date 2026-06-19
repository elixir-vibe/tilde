defmodule Tilde.Tool.View.ResultEntry do
  @moduledoc "Renderer-neutral semantic entry inside a tool result."

  @type t :: %__MODULE__{
          title: String.t(),
          metadata: String.t() | nil,
          body: [String.t()]
        }

  defstruct title: "", metadata: nil, body: []

  @spec new(String.t(), keyword()) :: t()
  def new(title, opts \\ []) do
    %__MODULE__{
      title: title,
      metadata: Keyword.get(opts, :metadata),
      body: Keyword.get(opts, :body, [])
    }
  end
end
