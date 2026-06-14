defmodule Tilde.Template do
  @moduledoc """
  Compiles HEEx templates into Tilde semantic view cells.

  Tilde reuses Phoenix's HEEx tokenizer/parser, then walks the parsed source tree
  into renderer-neutral `Tilde.View.Cell` values. It does not render HTML and parse
  it back; semantic Tilde components are read directly from the HEEx AST.
  """

  alias Tilde.Template.Source

  @doc "Compiles HEEx source in the caller context and returns semantic view cells."
  defmacro to_cells(source, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote do
      Tilde.Template.__to_cells__(unquote(source), unquote(opts), unquote(caller))
    end
  end

  @doc "Compiles HEEx source in the caller context and returns semantic view cells, raising on error."
  defmacro to_cells!(source, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote do
      case Tilde.Template.__to_cells__(unquote(source), unquote(opts), unquote(caller)) do
        {:ok, cells} -> cells
        {:error, reason} -> raise reason
      end
    end
  end

  @doc false
  def __to_cells__(source, opts, caller), do: Source.to_cells(source, opts, caller)
end
