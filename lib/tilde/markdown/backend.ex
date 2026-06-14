defmodule Tilde.Markdown.Backend do
  @moduledoc """
  Behaviour for Markdown rendering backends.
  """

  @callback to_html(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
