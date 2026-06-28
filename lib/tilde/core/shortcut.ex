defmodule Tilde.Core.Shortcut do
  @moduledoc """
  Renderer-neutral keyboard shortcut definition.

  Shortcuts are identified by stable semantic ids. Renderers display the
  configured key for an id and route keyboard input back to the same id rather
  than hardcoding keys in individual components.
  """

  defstruct id: "",
            keys: [],
            label: "",
            description: "",
            scopes: [],
            prevent_default?: false,
            capture_interactive?: false

  @type scope :: :chat | :workspace | :buffer | :palette

  @type t :: %__MODULE__{
          id: String.t(),
          keys: [String.t()],
          label: String.t(),
          description: String.t(),
          scopes: [scope()],
          prevent_default?: boolean(),
          capture_interactive?: boolean()
        }

  @doc "Builds a shortcut definition."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      keys: List.wrap(Keyword.get(opts, :keys, [])),
      label: Keyword.get(opts, :label, ""),
      description: Keyword.get(opts, :description, ""),
      scopes: List.wrap(Keyword.get(opts, :scopes, [])),
      prevent_default?: Keyword.get(opts, :prevent_default?, false),
      capture_interactive?: Keyword.get(opts, :capture_interactive?, false)
    }
  end
end
