defmodule Tilde.Runtime.LLM.Event do
  @moduledoc "Helpers for canonical Jido AI runtime events emitted at Tilde runtime boundaries."

  @spec failed(term(), keyword()) :: Jido.AI.Runtime.Event.t()
  def failed(reason, opts \\ []) do
    source = Keyword.get(opts, :source, "tilde-runtime")

    Jido.AI.Runtime.Event.new(%{
      seq: Keyword.get(opts, :seq, 0),
      run_id: source,
      request_id: source,
      iteration: Keyword.get(opts, :iteration, 0),
      kind: :request_failed,
      data: %{error: reason}
    })
  end
end
