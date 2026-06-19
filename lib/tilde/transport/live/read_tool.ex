defmodule Tilde.Transport.Live.ReadTool do
  @moduledoc "LiveView projection for expanded read tool content."

  alias Tilde.Renderer.SyntaxHighlight
  alias Tilde.Tool.View.Read

  @spec syntax_html(map()) :: String.t() | nil
  def syntax_html(%{name: "read", expanded?: true, lines: [_ | _]} = view) do
    view
    |> Read.source()
    |> SyntaxHighlight.to_html(Read.path(view))
  end

  def syntax_html(_view), do: nil
end
