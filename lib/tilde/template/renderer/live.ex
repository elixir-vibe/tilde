defmodule Tilde.Template.Renderer.Live do
  @moduledoc """
  Renders HEEx templates through Tilde semantic cells into LiveView markup.

  This mirrors `Tilde.Template.Renderer.TUI`: the template is first compiled to
  `Tilde.View.Cell` values, then rendered by the shared LiveView view renderer.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.ViewRenderer

  @doc "Compiles HEEx source and renders it through the shared LiveView renderer."
  defmacro render(source, opts \\ []) do
    quote do
      case Tilde.Template.to_cells(unquote(source), unquote(opts)) do
        {:ok, cells} -> {:ok, Tilde.Template.Renderer.Live.__render_cells__(cells)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Compiles HEEx source and renders it through the shared LiveView renderer, raising on error."
  defmacro render!(source, opts \\ []) do
    quote do
      case Tilde.Template.Renderer.Live.render(unquote(source), unquote(opts)) do
        {:ok, rendered} -> rendered
        {:error, reason} -> raise reason
      end
    end
  end

  @doc false
  def __render_cells__(cells) do
    assigns = %{cells: cells}

    ~H"""
    <.cell :for={cell <- @cells} cell={cell} />
    """
  end
end
