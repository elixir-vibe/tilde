defmodule Tilde.ToolRenderer do
  @moduledoc """
  Behaviour and registry for semantic tool rendering.

  Tool renderers derive compact call/result views from `Tilde.Block` values.
  They do not emit ANSI or HTML; terminal and LiveView renderers consume the
  returned semantic maps.
  """

  alias Tilde.Block

  @type segment :: %{
          required(:text) => String.t(),
          optional(:color) => :accent | :muted | :dim | :success
        }

  @type call_view :: %{
          title: String.t(),
          segments: [segment()],
          tags: [String.t()],
          suffix: String.t() | nil
        }

  @type result_view :: %{
          metadata_rows: [{atom(), String.t()}],
          lines: [String.t()],
          streams: [map()],
          hidden_lines: non_neg_integer(),
          waiting?: boolean()
        }

  @callback call(Block.t()) :: call_view()
  @callback result(Block.t(), keyword()) :: result_view()

  @doc "Builds a semantic tool call view."
  @spec call_view(String.t(), keyword()) :: call_view()
  def call_view(title, opts \\ []) when is_binary(title) do
    %{
      title: title,
      segments: Keyword.get(opts, :segments, []),
      tags: Keyword.get(opts, :tags, []),
      suffix: Keyword.get(opts, :suffix)
    }
  end

  @doc "Builds a semantic tool result view."
  @spec result_view(keyword()) :: result_view()
  def result_view(opts \\ []) do
    %{
      metadata_rows: Keyword.get(opts, :metadata_rows, []),
      lines: Keyword.get(opts, :lines, []),
      streams: Keyword.get(opts, :streams, []),
      hidden_lines: Keyword.get(opts, :hidden_lines, 0),
      waiting?: Keyword.get(opts, :waiting?, false)
    }
  end

  @doc "Returns the renderer module for a tool block or tool name."
  @spec for(Block.t() | String.t() | nil) :: module()
  def for(%Block{name: name}), do: __MODULE__.for(name)

  def for(name) do
    registry = Application.get_env(:tilde, :tool_renderers, default_registry())
    Map.get(registry, name, Tilde.ToolRenderer.Default)
  end

  @doc "Built-in tool renderer registry."
  @spec default_registry() :: %{String.t() => module()}
  def default_registry do
    %{
      "bash" => Tilde.ToolRenderer.Bash,
      "utc_now" => Tilde.ToolRenderer.UtcNow
    }
  end
end
