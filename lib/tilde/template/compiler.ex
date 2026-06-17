defmodule Tilde.Template.Compiler do
  @moduledoc false

  alias Phoenix.LiveView.TagEngine.Parser
  alias Tilde.View.{Cell, Helpers, Line, Text}

  @title_tags ~w(h1 h2 h3 h4 h5 h6 strong b)
  @accent_tags ~w(em i code a)

  @spec to_cells(String.t(), keyword(), Macro.Env.t()) ::
          {:ok, [Cell.t()]} | {:error, Exception.t()}
  def to_cells(source, opts, caller) do
    parser = parse!(source, caller)
    assigns = Keyword.get(opts, :assigns, %{})
    env = %{assigns: assigns, caller: caller}

    cells =
      parser.nodes
      |> Enum.flat_map(&node_to_cells(&1, env))
      |> case do
        [] -> [fallback_cell(parser.nodes, env, opts)]
        cells -> cells
      end

    {:ok, cells}
  rescue
    exception in [
      ArgumentError,
      CompileError,
      FunctionClauseError,
      KeyError,
      Phoenix.LiveView.TagEngine.Tokenizer.ParseError,
      RuntimeError,
      SyntaxError,
      TokenMissingError,
      UndefinedFunctionError
    ] ->
      {:error, exception}
  end

  defp parse!(source, caller) do
    Parser.parse!(source,
      file: caller.file,
      line: caller.line + 1,
      caller: caller,
      indentation: 0,
      tag_handler: Phoenix.LiveView.HTMLEngine
    )
  end

  defp node_to_cells({:block, type, name, attrs, children, _meta, _close_meta}, env)
       when type in [:local_component, :remote_component] do
    case component_name(name) do
      "cell" -> [cell_from_attrs(attrs, children, env)]
      "message" -> [message_from_attrs(attrs, children, env)]
      "markdown" -> [message_from_attrs(attrs, children, env, format: :markdown)]
      "tool" -> [template_cell_from_attrs(:tool, attrs, children, env)]
      "choice" -> [template_cell_from_attrs(:choice, attrs, children, env)]
      "suggest" -> [template_cell_from_attrs(:suggest, attrs, children, env)]
      _ -> []
    end
  end

  defp node_to_cells(_node, _env), do: []

  defp fallback_cell(nodes, env, opts) do
    Cell.new(
      kind: Keyword.get(opts, :kind, :template),
      role: Keyword.get(opts, :role),
      state: Keyword.get(opts, :state, :normal),
      lines: nodes_to_lines(nodes, env),
      padding_x: Keyword.get(opts, :padding_x, 0),
      padding_y: Keyword.get(opts, :padding_y, 0)
    )
  end

  defp cell_from_attrs(attrs, children, env) do
    attrs = attrs_map(attrs, env)
    lines = nodes_to_lines(children, env)

    Cell.new(
      kind: atom_attr(attrs, "kind", :template),
      role: atom_attr(attrs, "role", nil),
      state: atom_attr(attrs, "state", :normal),
      lines: lines,
      source: lines_to_text(lines),
      padding_x: int_attr(attrs, "padding_x", 0),
      padding_y: int_attr(attrs, "padding_y", 0),
      attrs: %{template: :source}
    )
  end

  defp template_cell_from_attrs(role, attrs, children, env) do
    attrs = attrs_map(attrs, env)
    lines = nodes_to_lines(children, env)

    Cell.new(
      kind: :template,
      role: role,
      state: atom_attr(attrs, "state", :normal),
      lines: lines,
      source: lines_to_text(lines),
      padding_x: int_attr(attrs, "padding_x", 1),
      padding_y: int_attr(attrs, "padding_y", 1),
      attrs: %{template: :source, semantic_kind: role}
    )
  end

  defp message_from_attrs(attrs, children, env, opts \\ []) do
    attrs = attrs_map(attrs, env)
    lines = children |> nodes_to_parts(env) |> parts_to_lines(:normal)
    format = Keyword.get(opts, :format, atom_attr(attrs, "format", :plain))

    Cell.new(
      kind: :message,
      role: atom_attr(attrs, "role", :assistant),
      format: format,
      source: lines_to_text(lines),
      lines: lines,
      padding_x: 0,
      padding_y: 0,
      attrs: %{template: :source}
    )
  end

  defp nodes_to_lines(nodes, env) do
    nodes
    |> Enum.flat_map(&node_to_lines(&1, env))
    |> Enum.reject(&(Helpers.plain_text(&1) == ""))
  end

  defp node_to_lines({:text, text, _meta}, _env) do
    text
    |> normalize_text()
    |> line_from_text()
    |> List.wrap()
  end

  defp node_to_lines({:body_expr, expr, _meta}, env) do
    expr |> eval_expr(env) |> to_string() |> line_from_text() |> List.wrap()
  end

  defp node_to_lines({:self_close, type, name, attrs, _meta}, env)
       when type in [:local_component, :remote_component] do
    component_to_lines(name, attrs, [], env)
  end

  defp node_to_lines({:block, type, name, attrs, children, _meta, _close_meta}, env)
       when type in [:local_component, :remote_component] do
    component_to_lines(name, attrs, children, env)
  end

  defp node_to_lines({:block, :tag, name, _attrs, children, _meta, _close_meta}, env)
       when name in ~w(ul ol tbody thead table),
       do: nodes_to_lines(children, env)

  defp node_to_lines({:block, :tag, "li", _attrs, children, _meta, _close_meta}, env) do
    [Line.new([Text.new("• ") | nodes_to_parts(children, env)])]
  end

  defp node_to_lines({:block, :tag, "tr", _attrs, children, _meta, _close_meta}, env) do
    cells = Enum.flat_map(children, &table_cell_parts(&1, env))

    if cells == [] do
      []
    else
      [Line.new(join_parts(cells, Text.new(" | ", :muted)))]
    end
  end

  defp node_to_lines({:block, :tag, "pre", _attrs, children, _meta, _close_meta}, env) do
    children
    |> raw_text(env)
    |> String.split("\n", trim: true)
    |> Enum.map(&Line.new(Text.new(&1, :accent), role: :primary))
  end

  defp node_to_lines({:block, :tag, name, _attrs, children, _meta, _close_meta}, env) do
    style = tag_style(name)

    children
    |> nodes_to_parts(env, style)
    |> parts_to_lines(role_for_style(style))
  end

  defp node_to_lines({:self_close, :tag, name, _attrs, _meta}, _env) when name in ~w(br hr),
    do: [:blank]

  defp node_to_lines(_node, _env), do: []

  defp component_to_lines(name, attrs, children, env) do
    attrs = attrs_map(attrs, env)

    case component_name(name) do
      "line" ->
        [Line.new(nodes_to_parts(children, env), role: atom_attr(attrs, "role", :normal))]

      "tool_call" ->
        [tool_call_line(attrs)]

      "item" ->
        [Line.new([Text.new("• ") | nodes_to_parts(children, env)])]

      inline when inline in ~w(title accent primary muted meta error success text code) ->
        style = inline_style(inline, attrs)
        [Line.new(nodes_to_parts(children, env, style), role: role_for_style(style))]

      _ ->
        []
    end
  end

  defp nodes_to_parts(nodes, env, forced_style \\ nil) do
    nodes
    |> Enum.flat_map(&node_to_parts(&1, env, forced_style))
    |> trim_parts()
  end

  defp node_to_parts({:text, text, _meta}, _env, forced_style) do
    text = normalize_part_text(text)
    if String.trim(text) == "", do: [], else: [Text.new(text, forced_style || :plain)]
  end

  defp node_to_parts({:body_expr, expr, _meta}, env, forced_style) do
    text = expr |> eval_expr(env) |> to_string()
    if text == "", do: [], else: [Text.new(text, forced_style || :plain)]
  end

  defp node_to_parts(
         {:block, :tag, name, _attrs, children, _meta, _close_meta},
         env,
         forced_style
       ) do
    nodes_to_parts(children, env, forced_style || tag_style(name))
  end

  defp node_to_parts({:self_close, :tag, name, _attrs, _meta}, _env, _forced_style)
       when name in ~w(br hr),
       do: [Text.new("\n")]

  defp node_to_parts({:block, type, name, attrs, children, _meta, _close_meta}, env, forced_style)
       when type in [:local_component, :remote_component] do
    attrs = attrs_map(attrs, env)

    case component_name(name) do
      inline when inline in ~w(title accent primary muted meta error success text code) ->
        style = inline_style(inline, attrs)
        nodes_to_parts(children, env, forced_style || style)

      _ ->
        []
    end
  end

  defp node_to_parts(_node, _env, _forced_style), do: []

  defp parts_to_lines(parts, role) do
    parts
    |> Enum.chunk_by(&(&1.text == "\n"))
    |> Enum.reject(&match?([%Text{text: "\n"}], &1))
    |> Enum.map(&Line.new(&1, role: role))
  end

  defp table_cell_parts({:block, :tag, name, _attrs, children, _meta, _close_meta}, env)
       when name in ~w(td th) do
    [nodes_to_parts(children, env, if(name == "th", do: :title, else: nil))]
  end

  defp table_cell_parts(_node, _env), do: []

  defp join_parts(parts, separator) do
    parts
    |> Enum.intersperse([separator])
    |> List.flatten()
  end

  defp raw_text(nodes, env) do
    Enum.map_join(nodes, fn
      {:text, text, _meta} -> text
      {:body_expr, expr, _meta} -> expr |> eval_expr(env) |> to_string()
      {:block, _type, _name, _attrs, children, _meta, _close_meta} -> raw_text(children, env)
      _node -> ""
    end)
  end

  defp line_from_text(text) do
    text = String.trim(text)
    if text == "", do: nil, else: Line.new(text)
  end

  defp tool_call_line(attrs) do
    segment = Map.get(attrs, "segment")
    suffix = Map.get(attrs, "suffix")

    Helpers.tool_call(to_string(Map.fetch!(attrs, "name")),
      segments: if(segment in [nil, ""], do: [], else: [%{text: segment, style: :accent}]),
      tags: List.wrap(Map.get(attrs, "tags", [])),
      suffix: suffix
    )
  end

  defp lines_to_text(lines), do: Enum.map_join(lines, "\n", &Helpers.plain_text/1)

  defp attrs_map(attrs, env) do
    Map.new(attrs, fn
      {name, {:string, value, _meta}, _attr_meta} -> {name, value}
      {name, {:expr, expr, _meta}, _attr_meta} -> {name, eval_expr(expr, env)}
      {name, nil, _attr_meta} -> {name, true}
    end)
  end

  defp eval_expr(expr, env) do
    ast =
      expr
      |> Code.string_to_quoted!(file: env.caller.file, line: env.caller.line)
      |> Macro.prewalk(&expand_assign/1)

    {value, _binding} =
      Code.eval_quoted(ast, [assigns: env.assigns], Macro.Env.prune_compile_info(env.caller))

    value
  end

  defp expand_assign({:@, meta, [{name, _, atom}]}) when is_atom(name) and is_atom(atom) do
    quote line: meta[:line] || 0 do
      Map.fetch!(var!(assigns), unquote(name))
    end
  end

  defp expand_assign(ast), do: ast

  defp inline_style("meta", _attrs), do: :muted
  defp inline_style(inline, attrs), do: atom_attr(attrs, "style", style_atom(inline))

  defp atom_attr(attrs, name, default) do
    case Map.get(attrs, name) do
      nil ->
        default

      "" ->
        default

      value when is_atom(value) ->
        value

      value ->
        allowed_atom(name, value, default)
    end
  end

  defp allowed_atom("format", value, default), do: known_atom(value, ~w(plain markdown), default)

  defp allowed_atom("kind", value, default),
    do: known_atom(value, ~w(template block message widget), default)

  defp allowed_atom("role", value, default),
    do:
      known_atom(
        value,
        ~w(normal metadata primary muted error title hint user assistant system),
        default
      )

  defp allowed_atom("state", value, default),
    do: known_atom(value, ~w(normal pending success error cancelled), default)

  defp allowed_atom("style", value, default),
    do:
      known_atom(
        value,
        ~w(plain title accent muted primary success error warning shortcut),
        default
      )

  defp allowed_atom(_name, _value, default), do: default

  defp known_atom(value, allowed, default) do
    value = value |> to_string() |> String.replace("-", "_")

    if value in allowed do
      String.to_existing_atom(value)
    else
      default
    end
  end

  defp style_atom("meta"), do: :muted
  defp style_atom("title"), do: :title
  defp style_atom("accent"), do: :accent
  defp style_atom("primary"), do: :primary
  defp style_atom("muted"), do: :muted
  defp style_atom("error"), do: :error
  defp style_atom("success"), do: :success
  defp style_atom("text"), do: :plain
  defp style_atom("code"), do: :accent

  defp int_attr(attrs, name, default) do
    case Map.get(attrs, name) do
      nil ->
        default

      value when is_integer(value) ->
        value

      value ->
        value
        |> to_string()
        |> Integer.parse()
        |> then(fn
          {int, _} -> int
          _ -> default
        end)
    end
  end

  defp component_name(name) do
    name |> to_string() |> String.split(".") |> List.last()
  end

  defp tag_style(name) when name in @title_tags, do: :title
  defp tag_style(name) when name in @accent_tags, do: :accent
  defp tag_style(_name), do: nil

  defp role_for_style(:title), do: :title
  defp role_for_style(:primary), do: :primary
  defp role_for_style(:muted), do: :muted
  defp role_for_style(:error), do: :error
  defp role_for_style(_style), do: :normal

  defp normalize_text(text) do
    text
    |> String.replace(["\r", "\n", "\t"], " ")
    |> String.split(" ", trim: true)
    |> Enum.join(" ")
  end

  defp normalize_part_text(text) do
    text
    |> String.replace(["\r", "\n", "\t"], " ")
    |> String.replace(<<194, 160>>, " ")
    |> collapse_spaces()
  end

  defp collapse_spaces(text) do
    text
    |> String.split(" ", trim: false)
    |> Enum.reduce([], fn
      "", [] -> [""]
      "", ["" | _] = acc -> acc
      part, acc -> [part | acc]
    end)
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp trim_parts(parts) do
    parts
    |> trim_first_part()
    |> trim_last_part()
    |> Enum.reject(&(&1.text == ""))
  end

  defp trim_first_part([%Text{} = part | rest]),
    do: [%Text{part | text: String.trim_leading(part.text)} | rest]

  defp trim_first_part(parts), do: parts

  defp trim_last_part(parts) do
    case Enum.reverse(parts) do
      [%Text{} = part | rest] ->
        Enum.reverse([%Text{part | text: String.trim_trailing(part.text)} | rest])

      parts ->
        Enum.reverse(parts)
    end
  end
end
