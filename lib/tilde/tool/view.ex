defmodule Tilde.Tool.View do
  @moduledoc """
  Struct-free semantic view constructors shared by tool viewers.
  """

  @type segment :: %{
          required(:text) => String.t(),
          optional(:color) => :accent | :muted | :dim | :success
        }

  @type call :: %{
          title: String.t(),
          segments: [segment()],
          tags: [String.t()],
          suffix: String.t() | nil
        }

  @type result :: %{
          metadata_rows: [{atom(), String.t()}],
          lines: [String.t()],
          streams: [map()],
          hidden_lines: non_neg_integer(),
          waiting?: boolean()
        }

  @spec call(String.t(), keyword()) :: call()
  def call(title, opts \\ []) when is_binary(title) do
    %{
      title: title,
      segments: Keyword.get(opts, :segments, []),
      tags: Keyword.get(opts, :tags, []),
      suffix: Keyword.get(opts, :suffix)
    }
  end

  @spec result(keyword()) :: result()
  def result(opts \\ []) do
    %{
      metadata_rows: Keyword.get(opts, :metadata_rows, []),
      lines: Keyword.get(opts, :lines, []),
      streams: Keyword.get(opts, :streams, []),
      hidden_lines: Keyword.get(opts, :hidden_lines, 0),
      waiting?: Keyword.get(opts, :waiting?, false)
    }
  end
end
