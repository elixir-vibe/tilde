defmodule Tilde.Runtime.LLM.Event do
  @moduledoc "Helpers for runtime events emitted at Tilde LLM boundaries."

  alias Tilde.Runtime.Event

  @spec failed(term(), keyword()) :: Event.t()
  def failed(reason, opts \\ []) do
    source = Keyword.get(opts, :source, "tilde-runtime")

    Event.new(%{
      seq: Keyword.get(opts, :seq, 0),
      run_id: source,
      request_id: source,
      iteration: Keyword.get(opts, :iteration, 0),
      kind: :request_failed,
      data: %{error: reason}
    })
  end
end
