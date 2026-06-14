defmodule Tilde.Markdown do
  @moduledoc """
  Markdown rendering boundary for Tilde.

  Tilde keeps Markdown as an input format rather than its core representation.
  When MDEx is available, this module renders Markdown to safe HTML using MDEx's
  default policy, which omits raw HTML unless explicitly configured otherwise.
  """

  @default_options [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true
    ]
  ]

  @doc "Renders Markdown to HTML with MDEx when available."
  @spec to_html(String.t(), keyword()) :: {:ok, String.t()} | {:error, :mdex_not_available}
  def to_html(markdown, opts \\ []) when is_binary(markdown) do
    if Code.ensure_loaded?(MDEx) do
      {:ok, MDEx.to_html!(markdown, options(opts))}
    else
      {:error, :mdex_not_available}
    end
  end

  defp options(opts) do
    Keyword.merge(@default_options, opts, fn _key, default, override ->
      Keyword.merge(default, override)
    end)
  end
end
