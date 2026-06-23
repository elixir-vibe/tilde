defmodule Tilde.Transport.Live.PanelTest do
  use TildeTest.Case

  import Phoenix.Component
  import Tilde.Transport.Live.Line
  import Tilde.Transport.Live.Panel

  alias Tilde.View.Heading

  test "renders shared panel anatomy with semantic line heading" do
    heading = Heading.line("choice", detail: "Apply patch?")

    html =
      render_component(
        fn assigns ->
          ~H"""
          <.panel id="choice_1" kind="choice">
            <:header>
              <span class="call"><.line line={@heading} /></span>
            </:header>
            <:body>
              <div class="options">body</div>
            </:body>
            <:footer>
              footer
            </:footer>
          </.panel>
          """
        end,
        %{heading: heading}
      )

    assert html =~ ~s|class="block choice"|
    assert html =~ ~s|class="header"|
    assert html =~ ~s|class="text title">choice</span>|
    assert html =~ ~s|class="text accent"> Apply patch?</span>|
    assert html =~ ~s|class="footer actions"|
  end
end
