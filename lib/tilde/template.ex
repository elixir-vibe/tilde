defmodule Tilde.Template do
  @moduledoc """
  Compiles HEEx templates into Tilde semantic view cells.

  This is intentionally an adapter, not a replacement for Phoenix's HEEx engine.
  Phoenix still parses HEEx, evaluates assigns, and invokes Phoenix components;
  Tilde then maps the rendered HTML into renderer-neutral `Tilde.View.Cell`
  values that can be rendered by LiveView, TUI, SSH, JSON, or text renderers.
  """

  alias Tilde.Template.HTML

  @doc "Compiles HEEx source in the caller context and returns rendered HTML."
  defmacro to_html(source, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote do
      Tilde.Template.__to_html__(unquote(source), unquote(opts), unquote(caller))
    end
  end

  @doc "Compiles HEEx source in the caller context and returns rendered HTML, raising on error."
  defmacro to_html!(source, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote do
      case Tilde.Template.__to_html__(unquote(source), unquote(opts), unquote(caller)) do
        {:ok, html} -> html
        {:error, reason} -> raise reason
      end
    end
  end

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
  def __to_cells__(source, opts, caller) do
    with {:ok, html} <- __to_html__(source, opts, caller) do
      {:ok, HTML.to_cells(html, opts)}
    end
  end

  @doc false
  def __to_html__(source, opts, caller) do
    assigns = Keyword.get(opts, :assigns, %{})

    rendered =
      Phoenix.LiveView.TagEngine.compile(source,
        engine: Phoenix.LiveView.Engine,
        file: caller.file,
        line: caller.line + 1,
        caller: caller,
        indentation: 0,
        tag_handler: Phoenix.LiveView.HTMLEngine,
        trim: true
      )

    {rendered, _binding} =
      Code.eval_quoted(rendered, [assigns: assigns], Macro.Env.prune_compile_info(caller))

    html =
      rendered
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    {:ok, html}
  rescue
    exception in [
      ArgumentError,
      CompileError,
      FunctionClauseError,
      Phoenix.LiveView.TagEngine.Tokenizer.ParseError,
      RuntimeError,
      SyntaxError,
      TokenMissingError,
      UndefinedFunctionError
    ] ->
      {:error, exception}
  end
end
