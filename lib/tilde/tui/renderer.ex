defmodule Tilde.TUI.Renderer do
  @moduledoc """
  ANSI terminal renderer for Tilde sessions.

  The renderer converts semantic session state into an `Inspect.Algebra` document,
  formats it for a terminal width, and wraps it in `IO.ANSI` control sequences.
  """

  @behaviour Tilde.Renderer

  alias Tilde.Session
  alias Tilde.TUI.Doc

  @doc "Renders a session as ANSI iodata."
  @impl true
  @spec render(Session.t(), keyword()) :: iodata()
  def render(%Session{} = session, opts \\ []) do
    width = Keyword.get(opts, :width, 80)
    ansi? = Keyword.get(opts, :ansi, true)
    # Keep ANSI styling out of Inspect.Algebra documents so width calculations
    # are based on visible text, not escape byte length. For now ANSI mode only
    # controls screen management; semantic color can be applied after layout in
    # a later renderer pass.
    doc = Doc.session(session, Keyword.put(opts, :ansi, false))
    body = Inspect.Algebra.format(doc, width)

    if ansi? do
      [IO.ANSI.clear(), IO.ANSI.home(), terminal_newlines(body), "\r\n"]
    else
      [body, "\n"]
    end
  end

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
