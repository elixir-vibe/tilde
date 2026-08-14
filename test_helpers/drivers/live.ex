defmodule TildeTest.Driver.Live do
  @moduledoc "Component-level LiveView driver for shared user-behavior tests."

  import Phoenix.LiveViewTest, only: [render_component: 2]

  @behaviour TildeTest.Driver

  alias Tilde.Core.Session
  alias Tilde.Session.Controller

  defstruct session: nil, html: ""

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
  def text(%__MODULE__{html: html}), do: strip_html(html)

  @doc "Returns rendered LiveView component HTML."
  @spec html(%__MODULE__{}) :: String.t()
  def html(%__MODULE__{html: html}), do: html

  @impl true
  def session(%__MODULE__{session: %Session{} = session}), do: session

  defp render(%__MODULE__{} = state) do
    html = render_component(&Tilde.Transport.Live.Console.console/1, session: state.session)
    %{state | html: html}
  end

  defp normalize_key(:escape), do: :cancel
  defp normalize_key(:ctrl_o), do: :toggle_expand
  defp normalize_key(key), do: key

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
