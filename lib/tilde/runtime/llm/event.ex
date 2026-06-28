defmodule Tilde.Runtime.LLM.Event do
  @moduledoc "Helpers for Jidoka runtime events emitted at Tilde runtime boundaries."

  @spec failed(term(), keyword()) :: Jidoka.Event.t()
  def failed(reason, opts \\ []) do
    source = Keyword.get(opts, :source, "tilde-runtime")

    Jidoka.Event.build(:turn_failed, [],
      seq: Keyword.get(opts, :seq, 0),
      agent_id: source,
      request_id: source,
      loop_index: Keyword.get(opts, :iteration, 0),
      data: %{error: reason}
    )
  end
end
