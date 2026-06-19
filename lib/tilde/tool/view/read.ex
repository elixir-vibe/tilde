defmodule Tilde.Tool.View.Read do
  @moduledoc "Read tool view helpers shared by renderer projections."

  @spec path(map()) :: String.t()
  def path(%{args: %{file_path: path}}), do: path_or_text(path)
  def path(%{args: %{"file_path" => path}}), do: path_or_text(path)
  def path(%{args: %{path: path}}), do: path_or_text(path)
  def path(%{args: %{"path" => path}}), do: path_or_text(path)
  def path(_view), do: "text"

  @spec source(map()) :: String.t()
  def source(%{lines: lines}) when is_list(lines), do: Enum.join(lines, "\n")
  def source(_view), do: ""

  defp path_or_text(path) when is_binary(path) and path != "", do: path
  defp path_or_text(_path), do: "text"
end
