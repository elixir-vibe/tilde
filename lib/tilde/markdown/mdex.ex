defmodule Tilde.Markdown.MDEx do
  @moduledoc """
  MDEx-backed Markdown renderer.

  This backend intentionally uses MDEx's safe default rendering policy. Raw HTML
  is omitted unless callers explicitly pass MDEx options that change that policy.
  """

  @behaviour Tilde.Markdown.Backend

  @default_options [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true
    ]
  ]

  @impl true
  def to_html(markdown, opts \\ []) when is_binary(markdown) do
    if Code.ensure_loaded?(MDEx) do
      {:ok, :erlang.apply(MDEx, :to_html!, [markdown, options(opts)])}
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
