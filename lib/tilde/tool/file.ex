defmodule Tilde.Tool.File do
  @moduledoc "Filesystem operations shared by model-facing Tilde tools."

  @type edit :: %{oldText: String.t(), newText: String.t()}

  @spec resolve(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve(path) when is_binary(path) do
    {:ok, Path.expand(path, File.cwd!())}
  end

  @spec list_directory(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def list_directory(path, opts \\ []) when is_binary(path) do
    with {:ok, absolute} <- resolve(path),
         {:ok, stat} <- File.stat(absolute),
         :ok <- ensure_directory(stat),
         {:ok, names} <- File.ls(absolute) do
      include_hidden? = Keyword.get(opts, :all, false)
      limit = Keyword.get(opts, :limit)

      entries =
        names
        |> maybe_drop_hidden(include_hidden?)
        |> Enum.sort()
        |> Enum.map(&directory_entry(path, absolute, &1))

      shown = if is_integer(limit), do: Enum.take(entries, limit), else: entries

      {:ok,
       %{
         path: path,
         entries: shown,
         total_entries: length(entries),
         selected_entries: length(shown)
       }}
    end
  rescue
    error in [File.Error, MatchError, ArgumentError] -> {:error, Exception.message(error)}
  end

  @spec read_text(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def read_text(path, opts \\ []) when is_binary(path) do
    with {:ok, absolute} <- resolve(path),
         {:ok, stat} <- File.stat(absolute),
         :ok <- ensure_regular(stat),
         {:ok, content} <- File.read(absolute) do
      offset = Keyword.get(opts, :offset)
      limit = Keyword.get(opts, :limit)
      lines = String.split(content, "\n", trim: false)
      total_lines = length(lines)
      start_index = max((offset || 1) - 1, 0)

      if start_index >= total_lines do
        {:error, "Offset #{offset} is beyond end of file (#{total_lines} lines total)"}
      else
        selected = select_lines(lines, start_index, limit)
        text = Enum.join(selected, "\n")

        {:ok,
         %{path: path, content: text, total_lines: total_lines, selected_lines: length(selected)}}
      end
    end
  end

  @spec write_text(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def write_text(path, content) when is_binary(path) and is_binary(content) do
    with {:ok, absolute} <- resolve(path),
         :ok <- File.mkdir_p(Path.dirname(absolute)) do
      old = if File.exists?(absolute), do: File.read!(absolute), else: ""
      :ok = File.write(absolute, content)
      diff = diff(old, content)

      {:ok,
       %{
         path: path,
         message: if(old == "", do: "Created #{path}.", else: "Wrote #{path}."),
         diff: diff,
         patch: unified_patch(path, old, content),
         firstChangedLine: first_changed_line(diff)
       }}
    end
  rescue
    error in [File.Error, MatchError, ArgumentError] -> {:error, Exception.message(error)}
  end

  @spec edit_text(String.t(), [map()]) :: {:ok, map()} | {:error, String.t()}
  def edit_text(path, edits) when is_binary(path) and is_list(edits) do
    with {:ok, absolute} <- resolve(path),
         {:ok, original} <- File.read(absolute),
         {:ok, edited, count} <- apply_edits(path, original, edits) do
      :ok = File.write(absolute, edited)
      diff = diff(original, edited)

      {:ok,
       %{
         path: path,
         message: "Successfully replaced #{count} block(s) in #{path}.",
         diff: diff,
         patch: unified_patch(path, original, edited),
         replacements: count,
         firstChangedLine: first_changed_line(diff)
       }}
    end
  rescue
    error in [File.Error, MatchError, ArgumentError] -> {:error, Exception.message(error)}
  end

  defp ensure_directory(%File.Stat{type: :directory}), do: :ok
  defp ensure_directory(%File.Stat{type: type}), do: {:error, "not a directory: #{type}"}

  defp ensure_regular(%File.Stat{type: :regular}), do: :ok
  defp ensure_regular(%File.Stat{type: type}), do: {:error, "not a regular file: #{type}"}

  defp maybe_drop_hidden(names, true), do: names
  defp maybe_drop_hidden(names, _all?), do: Enum.reject(names, &String.starts_with?(&1, "."))

  defp directory_entry(path, absolute, name) do
    full_path = Path.join(absolute, name)
    display_path = Path.join(path, name)

    case File.stat(full_path) do
      {:ok, %File.Stat{type: type, size: size}} ->
        %{name: name, path: display_path, type: type, size: size}

      {:error, reason} ->
        %{name: name, path: display_path, type: :unknown, error: inspect(reason)}
    end
  end

  defp select_lines(lines, start_index, nil), do: Enum.drop(lines, start_index)

  defp select_lines(lines, start_index, limit) when is_integer(limit),
    do: Enum.slice(lines, start_index, limit)

  defp select_lines(lines, start_index, _limit), do: Enum.drop(lines, start_index)

  defp apply_edits(_path, content, []), do: {:ok, content, 0}

  defp apply_edits(path, content, edits) do
    normalized = Enum.map(edits, &normalize_edit/1)

    with :ok <- validate_edits(path, content, normalized) do
      edited =
        normalized
        |> matches(content)
        |> Enum.sort_by(& &1.index, :desc)
        |> Enum.reduce(content, fn match, acc ->
          prefix = binary_part(acc, 0, match.index)
          suffix_start = match.index + byte_size(match.oldText)
          suffix = binary_part(acc, suffix_start, byte_size(acc) - suffix_start)
          IO.iodata_to_binary([prefix, match.newText, suffix])
        end)

      if edited == content do
        {:error, "No changes made to #{path}. The replacements produced identical content."}
      else
        {:ok, edited, length(normalized)}
      end
    end
  end

  defp normalize_edit(%{oldText: old, newText: new}), do: %{oldText: old, newText: new}
  defp normalize_edit(%{"oldText" => old, "newText" => new}), do: %{oldText: old, newText: new}
  defp normalize_edit(%{old_text: old, new_text: new}), do: %{oldText: old, newText: new}
  defp normalize_edit(%{"old_text" => old, "new_text" => new}), do: %{oldText: old, newText: new}
  defp normalize_edit(_edit), do: %{oldText: nil, newText: nil}

  defp validate_edits(path, content, edits) do
    edits
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {edit, index}, :ok ->
      occurrences = if is_binary(edit.oldText), do: occurrences(content, edit.oldText), else: 0

      cond do
        not is_binary(edit.oldText) or not is_binary(edit.newText) ->
          {:halt,
           {:error, "edits[#{index}] in #{path} must include oldText and newText strings."}}

        edit.oldText == "" ->
          {:halt, {:error, "edits[#{index}].oldText must not be empty in #{path}."}}

        occurrences == 0 ->
          {:halt,
           {:error,
            "Could not find edits[#{index}] in #{path}. The oldText must match exactly including all whitespace and newlines."}}

        occurrences > 1 ->
          {:halt,
           {:error,
            "Found #{occurrences} occurrences of edits[#{index}] in #{path}. Each oldText must be unique. Please provide more context to make it unique."}}

        true ->
          {:cont, :ok}
      end
    end)
    |> then(fn
      :ok -> validate_non_overlapping(path, content, edits)
      error -> error
    end)
  end

  defp validate_non_overlapping(path, content, edits) do
    content
    |> matches(edits)
    |> Enum.sort_by(& &1.index)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [left, right] -> left.index + byte_size(left.oldText) > right.index end)
    |> case do
      nil ->
        :ok

      [left, right] ->
        {:error,
         "edits[#{left.edit_index}] and edits[#{right.edit_index}] overlap in #{path}. Merge them into one edit or target disjoint regions."}
    end
  end

  defp matches(edits, content) when is_list(edits), do: matches(content, edits)

  defp matches(content, edits) do
    edits
    |> Enum.with_index()
    |> Enum.map(fn {edit, index} ->
      {match_index, _length} = :binary.match(content, edit.oldText)
      %{index: match_index, oldText: edit.oldText, newText: edit.newText, edit_index: index}
    end)
  end

  defp occurrences(content, text), do: content |> :binary.matches(text) |> length()

  @spec diff(String.t(), String.t()) :: String.t()
  def diff(old, new) when is_binary(old) and is_binary(new) do
    old_lines = split_lines(old)
    new_lines = split_lines(new)
    width = max(length(old_lines), length(new_lines)) |> Integer.digits() |> length()

    old_lines
    |> List.myers_difference(new_lines)
    |> diff_groups(width, 1, 1, [])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp unified_patch(path, old, new),
    do: ["--- a/#{path}", "+++ b/#{path}", diff(old, new)] |> Enum.join("\n")

  defp split_lines(""), do: []

  defp split_lines(text) do
    lines = String.split(text, "\n", trim: false)
    if String.ends_with?(text, "\n"), do: Enum.drop(lines, -1), else: lines
  end

  defp diff_groups([], _width, _old_line, _new_line, acc), do: acc

  defp diff_groups([{:eq, lines} | rest], width, old_line, new_line, acc) do
    count = length(lines)

    rendered =
      Enum.with_index(lines, old_line)
      |> Enum.map(fn {line, number} -> " #{pad(number, width)}  #{line}" end)

    diff_groups(rest, width, old_line + count, new_line + count, Enum.reverse(rendered, acc))
  end

  defp diff_groups([{:del, lines} | rest], width, old_line, new_line, acc) do
    rendered =
      Enum.with_index(lines, old_line)
      |> Enum.map(fn {line, number} -> "-#{pad(number, width)}  #{line}" end)

    diff_groups(rest, width, old_line + length(lines), new_line, Enum.reverse(rendered, acc))
  end

  defp diff_groups([{:ins, lines} | rest], width, old_line, new_line, acc) do
    rendered =
      Enum.with_index(lines, new_line)
      |> Enum.map(fn {line, number} -> "+#{pad(number, width)}  #{line}" end)

    diff_groups(rest, width, old_line, new_line + length(lines), Enum.reverse(rendered, acc))
  end

  defp pad(number, width), do: number |> Integer.to_string() |> String.pad_leading(width)

  defp first_changed_line(""), do: nil

  defp first_changed_line(diff) do
    diff
    |> String.split("\n")
    |> Enum.find_value(fn
      "+" <> rest ->
        rest
        |> String.trim_leading()
        |> String.split(" ", parts: 2)
        |> hd()
        |> Integer.parse()
        |> case do
          {n, _} -> n
          _ -> nil
        end

      _line ->
        nil
    end)
  end
end
