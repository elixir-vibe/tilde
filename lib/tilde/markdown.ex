defmodule Tilde.Markdown do
  @moduledoc """
  Markdown rendering boundary for Tilde.

  Tilde keeps Markdown as an input format rather than its core representation.
  The concrete Markdown implementation is a behaviour-backed backend configured
  through `:tilde, :markdown_backend` and defaults to `Tilde.Markdown.MDEx`.
  """

  @default_backend Tilde.Markdown.MDEx

  @doc "Renders Markdown to HTML with the configured backend."
  @spec to_html(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_html(markdown, opts \\ []) when is_binary(markdown) do
    backend().to_html(markdown, opts)
  end

  @doc "Returns the configured Markdown backend."
  @spec backend() :: module()
  def backend do
    Application.get_env(:tilde, :markdown_backend, @default_backend)
  end
end
