defmodule Tilde.Transport.SSH.Rendering do
  @moduledoc "Pure SSH/TUI rendering helpers for normal-screen channel output."

  alias Tilde.Core.{Block, Index, Input, Session}
  alias Tilde.Index.View, as: IndexView
  alias Tilde.Renderer.TUI
  alias Tilde.Renderer.TUI.{ViewRenderer, WidgetRenderer}

  @spec index(Index.t(), pos_integer()) :: iodata()
  def index(%Index{} = index, width) do
    index
    |> IndexView.widgets()
    |> WidgetRenderer.render(width, ansi: true)
  end

  @spec session(Session.t(), pos_integer(), pos_integer()) :: iodata()
  def session(%Session{} = session, width, height) do
    TUI.render(session, width: width, height: height, clear?: false)
  end

  @spec session_snapshot(Session.t(), String.t() | nil, String.t(), pos_integer(), pos_integer()) ::
          iodata()
  def session_snapshot(%Session{} = session, session_id, label, width, height) do
    [
      "\r",
      IO.ANSI.clear_line(),
      IO.ANSI.faint(),
      label,
      ": #{session_id || session.id}",
      IO.ANSI.normal(),
      "\r\n\r\n",
      session(session, width, height)
    ]
  end

  @spec session_info(Session.t(), String.t() | nil, boolean()) :: iodata()
  def session_info(%Session{} = session, session_id, attached?) do
    id = session_id || session.id
    mode = if attached?, do: "attached", else: "private"

    [
      "\r",
      IO.ANSI.clear_line(),
      IO.ANSI.faint(),
      "session: ",
      IO.ANSI.normal(),
      id,
      "\r\n",
      IO.ANSI.faint(),
      "mode: ",
      IO.ANSI.normal(),
      mode,
      "\r\n",
      IO.ANSI.faint(),
      "web: ",
      IO.ANSI.normal(),
      "/tilde/#{id}",
      "\r\n",
      IO.ANSI.faint(),
      "commands: ",
      IO.ANSI.normal(),
      "/attach <name> · /detach · /session",
      "\r\n\r\n"
    ]
  end

  @spec prompt(Session.t()) :: iodata()
  def prompt(%Session{} = session) do
    ["\r", IO.ANSI.clear_line(), TUI.render_prompt(session, ansi: true)]
  end

  @spec input_change(Input.t(), Input.t(), Session.t()) :: iodata()
  def input_change(%Input{} = old, %Input{} = new, %Session{} = session) do
    case appended_prompt_delta(old, new) do
      {:ok, delta} -> delta
      :redraw -> prompt(session)
    end
  end

  @spec blocks([Block.t()], Session.t(), pos_integer(), keyword()) :: iodata()
  def blocks(blocks, %Session{} = session, width, opts \\ []) when is_list(blocks) do
    prompt? = Keyword.get(opts, :prompt?, true)

    content =
      blocks
      |> Enum.map_join("\n\n", &block(&1, width))
      |> terminal_newlines()

    [
      "\r",
      IO.ANSI.clear_line(),
      content,
      if(prompt?, do: ["\r\n\r\n", TUI.render_prompt(session, ansi: true)], else: "")
    ]
  end

  @spec text(iodata()) :: iodata()
  def text(iodata), do: terminal_newlines(iodata)

  @spec tool_delta(atom(), iodata(), boolean()) :: iodata()
  def tool_delta(kind, text, true) do
    ["\r\n", IO.ANSI.faint(), to_string(kind), IO.ANSI.normal(), "\r\n", terminal_newlines(text)]
  end

  def tool_delta(_kind, text, false), do: terminal_newlines(text)

  @spec prompt_after_turn(Session.t()) :: iodata()
  def prompt_after_turn(%Session{} = session),
    do: ["\r\n\r\n", TUI.render_prompt(session, ansi: true)]

  @spec block(Block.t(), pos_integer()) :: iodata()
  def block(%Block{kind: :message, role: :user, source: source}, _width), do: source

  def block(%Block{kind: :message, role: role, source: source}, _width) do
    [IO.ANSI.faint(), to_string(role), IO.ANSI.normal(), "\n", source]
  end

  def block(%Block{} = block, width) do
    block
    |> Tilde.Viewable.to_view()
    |> ViewRenderer.render(width, ansi: true)
  end

  @spec terminal_newlines(iodata()) :: String.t()
  def terminal_newlines(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.replace("\n", "\r\n")
  end

  defp appended_prompt_delta(%Input{} = old, %Input{} = new) do
    if old.cursor == String.length(old.value) and
         new.cursor == String.length(new.value) and
         String.starts_with?(new.value, old.value) do
      {:ok, String.replace_prefix(new.value, old.value, "")}
    else
      :redraw
    end
  end
end
