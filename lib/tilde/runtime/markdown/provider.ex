defmodule Tilde.Runtime.Markdown.Provider do
  @moduledoc """
  Behaviour for Markdown rendering backends.
  """

  @callback to_html(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
