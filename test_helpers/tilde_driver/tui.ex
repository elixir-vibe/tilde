defmodule TildeTest.Driver.TUI do
  @moduledoc "Renderer-level TUI driver for shared user-behavior tests."

  @behaviour TildeTest.Driver

  alias Tilde.Core.{Controller, Session}

  defstruct session: nil, text: ""

  @impl true
  def open(opts \\ []) do
    session = Keyword.get_lazy(opts, :session, &Tilde.session/0)
    render(%__MODULE__{session: session})
  end

  @impl true
  def type(%__MODULE__{} = state, text) when is_binary(text) do
    Enum.reduce(String.graphemes(text), state, fn grapheme, state ->
      press(state, {:text, grapheme})
    end)
  end

  @impl true
  def press(%__MODULE__{} = state, key) do
    {:cont, session} = Controller.apply_key(state.session, normalize_key(key))
    render(%{state | session: session})
  end

  @impl true
  def text(%__MODULE__{text: text}), do: text

  @impl true
  def session(%__MODULE__{session: %Session{} = session}), do: session

  defp render(%__MODULE__{} = state) do
    text =
      state.session
      |> Tilde.Renderer.TUI.render(ansi: false, height: nil)
      |> IO.iodata_to_binary()

    %{state | text: text}
  end

  defp normalize_key(:escape), do: :cancel
  defp normalize_key(:ctrl_o), do: :toggle_expand
  defp normalize_key(key), do: key
end
