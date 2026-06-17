defmodule Tilde.Transport.OutcomeAdapterTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Interaction.Outcome
  alias Tilde.Transport.SSH.Outcome, as: SSHOutcome

  test "SSH outcomes dispatch through transport handlers" do
    state = []

    state =
      SSHOutcome.apply(
        state,
        [
          Outcome.complete_input("ignored"),
          Outcome.open_session("demo"),
          Outcome.open_index(),
          Outcome.show_session_info()
        ],
        attach: fn state, id -> [{:attach, id} | state] end,
        detach: fn state -> [:detach | state] end,
        show_session_info: fn state -> [:session_info | state] end
      )

    assert Enum.reverse(state) == [{:attach, "demo"}, :detach, :session_info]
  end
end
