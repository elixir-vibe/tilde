defmodule Tilde.Transport.SSH.Outcome do
  @moduledoc "Applies transport-neutral interaction outcomes to SSH channel state."

  alias Tilde.Core.Interaction.Outcome

  @type handler :: (term() -> term())
  @type session_handler :: (term(), String.t(), map() -> term())

  @spec apply(term(), [Outcome.t()], keyword()) :: term()
  def apply(state, outcomes, opts) when is_list(outcomes) and is_list(opts) do
    attach = Keyword.fetch!(opts, :attach)
    detach = Keyword.fetch!(opts, :detach)
    show_session_info = Keyword.fetch!(opts, :show_session_info)

    Enum.reduce(outcomes, state, fn
      %Outcome{type: :complete_input}, state ->
        state

      %Outcome{type: :open_session, payload: %{id: id} = payload}, state ->
        attach.(state, id, payload)

      %Outcome{type: :open_index}, state ->
        detach.(state)

      %Outcome{type: :show_session_info}, state ->
        show_session_info.(state)
    end)
  end
end
