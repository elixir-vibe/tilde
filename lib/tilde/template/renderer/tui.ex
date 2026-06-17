defmodule Tilde.Template.Renderer.TUI do
  @moduledoc """
  Renders HEEx templates to terminal text through Tilde semantic view cells.

  The template is compiled with Phoenix HEEx in the caller context, so imported
  Phoenix function components work as they do in `~H`. The resulting HTML is
  adapted into `Tilde.View.Cell` values before ANSI rendering.
  """

  @doc "Compiles HEEx source and renders it as ANSI terminal text."
  defmacro render(source, width, opts \\ []) do
    quote do
      case Tilde.Template.to_cells(unquote(source), unquote(opts)) do
        {:ok, cells} ->
          {:ok,
           cells
           |> Enum.map_join(
             "\n",
             &Tilde.Renderer.TUI.ViewRenderer.render(&1, unquote(width), unquote(opts))
           )}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Compiles HEEx source and renders it as ANSI terminal text, raising on error."
  defmacro render!(source, width, opts \\ []) do
    quote do
      case Tilde.Template.Renderer.TUI.render(unquote(source), unquote(width), unquote(opts)) do
        {:ok, text} -> text
        {:error, reason} -> raise reason
      end
    end
  end
end
