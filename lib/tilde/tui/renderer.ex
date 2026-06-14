defmodule Tilde.TUI.Renderer do
  @moduledoc """
  ANSI terminal renderer for Tilde sessions.

  The renderer converts semantic session state into shared Tilde view cells and
  paints those cells as width-aware terminal blocks. ANSI is renderer output
  only; semantic session state remains DOM/terminal independent.
  """

  @behaviour Tilde.Renderer

  alias Tilde.Session
  alias Tilde.TUI.{Theme, ViewRenderer}
  alias Tilde.View.Builder

  @doc "Renders a session as ANSI iodata."
  @impl true
  @spec render(Session.t(), keyword()) :: iodata()
  def render(%Session{} = session, opts \\ []) do
    width = Keyword.get(opts, :width, 80)
    ansi? = Keyword.get(opts, :ansi, true)
    opts = Keyword.put(opts, :ansi, ansi?)
    height = Keyword.get(opts, :height)
    body = session |> render_body(width, opts) |> maybe_clip_to_height(height)

    if ansi? do
      [IO.ANSI.home(), IO.ANSI.clear(), terminal_newlines(body)]
    else
      [body, "\n"]
    end
  end

  defp render_body(%Session{} = session, width, opts) do
    [
      Theme.title("# tilde", opts),
      render_blocks(session, width, opts),
      render_widgets(session, width, opts),
      render_footer(session, opts),
      render_input(session, opts)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp render_blocks(%Session{} = session, width, opts) do
    Enum.map_join(session.transcript.blocks, "\n\n", fn block ->
      block |> Builder.block() |> ViewRenderer.render(width, opts)
    end)
  end

  defp render_widgets(%Session{} = session, width, opts) do
    session.widgets
    |> Enum.flat_map(fn {_placement, widgets} -> widgets end)
    |> Enum.map_join("\n", fn widget ->
      widget |> Builder.widget() |> ViewRenderer.render(width, opts)
    end)
  end

  @doc "Renders only the prompt/input line."
  @spec render_prompt(Session.t(), keyword()) :: iodata()
  def render_prompt(%Session{} = session, opts \\ []), do: render_input(session, opts)

  defp render_input(%Session{} = session, opts) do
    value = session.input.value
    cursor = min(session.input.cursor, String.length(value))
    {left, right} = value |> String.graphemes() |> Enum.split(cursor)

    cursor = if Keyword.get(opts, :ansi, true), do: "", else: "▌"

    [
      Theme.accent(">", opts),
      " ",
      Enum.join(left),
      Theme.muted(cursor, opts),
      Enum.join(right)
    ]
    |> IO.iodata_to_binary()
  end

  defp render_footer(%Session{} = session, opts) do
    status = Enum.map_join(session.statuses, " · ", fn {key, value} -> "#{key}: #{value}" end)
    if status == "", do: "", else: Theme.muted(status, opts)
  end

  defp maybe_clip_to_height(body, nil), do: body

  defp maybe_clip_to_height(body, height) when is_integer(height) and height > 0 do
    body
    |> String.split("\n")
    |> Enum.take(-height)
    |> Enum.join("\n")
  end

  defp maybe_clip_to_height(body, _height), do: body

  defp terminal_newlines(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.replace("\n", "\r\n")
  end

  @doc "Renders a session and converts the result to a binary."
  @spec render_to_string(Session.t(), keyword()) :: String.t()
  def render_to_string(%Session{} = session, opts \\ []) do
    session
    |> render(opts)
    |> IO.iodata_to_binary()
  end
end
