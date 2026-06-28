defmodule Tilde.Runtime.CodeIntelligence do
  @moduledoc """
  Runtime source-code intelligence boundary.

  This first implementation uses Sourceror for local document symbols. Richer
  project-aware intelligence can later sit behind this same boundary.
  """

  alias Tilde.Core.FileSymbol

  @symbol_forms [:defmodule, :def, :defp, :defmacro, :defmacrop, :defdelegate, :defstruct, :@]
  @type_attributes [:type, :typep, :opaque]
  @callback_attributes [:callback, :macrocallback]

  @doc "Extracts document symbols from Elixir source."
  @spec document_symbols(String.t(), String.t()) :: [FileSymbol.t()]
  def document_symbols(source, path) when is_binary(source) and is_binary(path) do
    if elixir?(path) do
      source
      |> Sourceror.parse_string!()
      |> collect_symbols()
    else
      []
    end
  rescue
    _exception in [SyntaxError, TokenMissingError, ArgumentError] -> []
  end

  defp elixir?(path), do: Path.extname(path) in [".ex", ".exs"]

  defp collect_symbols(ast) do
    {_ast, symbols} =
      Macro.prewalk(ast, [], fn
        {form, meta, args} = node, acc when form in @symbol_forms ->
          {node, maybe_symbol(form, meta, args, acc)}

        node, acc ->
          {node, acc}
      end)

    symbols
    |> Enum.reverse()
    |> Enum.sort_by(&{&1.line, &1.column, &1.name})
  end

  defp maybe_symbol(form, meta, args, acc) do
    case symbol(form, meta, args) do
      %FileSymbol{} = symbol -> [symbol | acc]
      nil -> acc
    end
  end

  defp symbol(:defmodule, meta, [module_ast, _body]) do
    new_symbol(:module, module_name(module_ast), meta, "module")
  end

  defp symbol(:def, meta, [call_ast | _]) do
    function_symbol(:function, "def", call_ast, meta)
  end

  defp symbol(:defp, meta, [call_ast | _]) do
    function_symbol(:function, "defp", call_ast, meta)
  end

  defp symbol(:defmacro, meta, [call_ast | _]) do
    function_symbol(:macro, "defmacro", call_ast, meta)
  end

  defp symbol(:defmacrop, meta, [call_ast | _]) do
    function_symbol(:macro, "defmacrop", call_ast, meta)
  end

  defp symbol(:defdelegate, meta, [call_ast | _]) do
    function_symbol(:delegate, "defdelegate", call_ast, meta)
  end

  defp symbol(:defstruct, meta, _args) do
    new_symbol(:struct, "defstruct", meta, "defstruct")
  end

  defp symbol(:@, meta, [
         {attribute, _attribute_meta, [{:"::", _spec_meta, [call_ast, _type_ast]}]}
       ])
       when attribute in @type_attributes do
    type_symbol(attribute, call_ast, meta)
  end

  defp symbol(:@, meta, [
         {attribute, _attribute_meta, [{:"::", _spec_meta, [call_ast, _type_ast]}]}
       ])
       when attribute in @callback_attributes do
    callback_symbol(attribute, call_ast, meta)
  end

  defp symbol(_form, _meta, _args), do: nil

  defp function_symbol(kind, prefix, call_ast, meta) do
    {name, arity} = call_name_arity(call_ast)
    display = display_name(prefix, name, arity)

    new_symbol(kind, display, meta, prefix)
  end

  defp type_symbol(attribute, call_ast, meta) do
    {name, arity} = call_name_arity(call_ast)
    prefix = "@#{attribute}"

    new_symbol(:type, display_name(prefix, name, arity), meta, prefix)
  end

  defp callback_symbol(attribute, call_ast, meta) do
    {name, arity} = call_name_arity(call_ast)
    prefix = "@#{attribute}"

    new_symbol(:callback, display_name(prefix, name, arity), meta, prefix)
  end

  defp display_name(prefix, name, arity) do
    if is_integer(arity), do: "#{prefix} #{name}/#{arity}", else: "#{prefix} #{name}"
  end

  defp call_name_arity({:when, _meta, [call_ast | _guards]}), do: call_name_arity(call_ast)

  defp call_name_arity({name, _meta, args}) when is_atom(name) and is_list(args) do
    {Atom.to_string(name), length(args)}
  end

  defp call_name_arity({name, _meta, nil}) when is_atom(name), do: {Atom.to_string(name), 0}
  defp call_name_arity(other), do: {Macro.to_string(other), nil}

  defp module_name({:__aliases__, _meta, parts}), do: Module.concat(parts) |> inspect()
  defp module_name(other), do: Macro.to_string(other)

  defp new_symbol(kind, name, meta, detail) when is_binary(name) do
    FileSymbol.new(
      name: name,
      kind: kind,
      line: Keyword.get(meta, :line, 1),
      column: Keyword.get(meta, :column, 1),
      end_line: end_line(meta),
      end_column: end_column(meta),
      detail: detail
    )
  end

  defp end_line(meta) do
    end_meta = Keyword.get(meta, :end)
    expression_meta = Keyword.get(meta, :end_of_expression)

    line_from_meta(end_meta) || line_from_meta(expression_meta) || Keyword.get(meta, :line, 1)
  end

  defp end_column(meta) do
    end_meta = Keyword.get(meta, :end)
    expression_meta = Keyword.get(meta, :end_of_expression)

    column_from_meta(end_meta) || column_from_meta(expression_meta) ||
      Keyword.get(meta, :column, 1)
  end

  defp line_from_meta(meta) when is_list(meta), do: Keyword.get(meta, :line)
  defp line_from_meta(_meta), do: nil

  defp column_from_meta(meta) when is_list(meta), do: Keyword.get(meta, :column)
  defp column_from_meta(_meta), do: nil
end
