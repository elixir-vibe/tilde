defmodule Tilde.Session.AgentLoop.ResumeCandidate do
  @moduledoc "Validated checkpoint metadata for a possible future agent loop resume."

  alias Tilde.Core.{AgentRuntime, Session}

  @enforce_keys [:session_id, :run_id, :request_id, :checkpoint_token]
  defstruct [
    :session_id,
    :input_index,
    :block_id,
    :run_id,
    :request_id,
    :checkpoint_token,
    :iteration
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          input_index: pos_integer() | nil,
          block_id: String.t() | nil,
          run_id: String.t(),
          request_id: String.t(),
          checkpoint_token: String.t(),
          iteration: non_neg_integer() | nil
        }

  @spec from_session(Session.t()) :: t() | nil
  def from_session(%Session{} = session) do
    runtime = Session.agent_runtime(session)

    if resumable?(session, runtime) do
      %__MODULE__{
        session_id: session.id,
        input_index: runtime.input_index,
        block_id: runtime.block_id,
        run_id: runtime.run_id,
        request_id: runtime.request_id,
        checkpoint_token: runtime.checkpoint_token,
        iteration: runtime.iteration
      }
    end
  end

  defp resumable?(%Session{} = session, %AgentRuntime{} = runtime) do
    runtime.active? and
      not Session.assistant_active?(session) and
      present?(runtime.run_id) and
      present?(runtime.request_id) and
      present?(runtime.checkpoint_token)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
