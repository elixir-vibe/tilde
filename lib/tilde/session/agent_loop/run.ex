defmodule Tilde.Session.AgentLoop.Run do
  @moduledoc "Runtime identity for the active Jidoka turn."

  alias Tilde.Session.AgentLoop.ResumeCandidate

  @enforce_keys [:run_id, :request_id]
  defstruct [:run_id, :request_id, :checkpoint_token, :iteration]

  @type t :: %__MODULE__{
          run_id: String.t(),
          request_id: String.t(),
          checkpoint_token: String.t() | nil,
          iteration: non_neg_integer() | nil
        }

  @spec from_event(Jidoka.Event.t()) :: t()
  def from_event(%Jidoka.Event{} = event) do
    %__MODULE__{
      run_id: event.agent_id || event.request_id || event.effect_id,
      request_id: event.request_id,
      iteration: event.loop_index
    }
  end

  @spec from_resume_candidate(ResumeCandidate.t()) :: t()
  def from_resume_candidate(%ResumeCandidate{} = candidate) do
    %__MODULE__{
      run_id: candidate.run_id,
      request_id: candidate.request_id,
      checkpoint_token: candidate.checkpoint_token,
      iteration: candidate.iteration
    }
  end

  @spec put_checkpoint(t() | nil, Jidoka.Event.t()) :: t() | nil
  def put_checkpoint(nil, %Jidoka.Event{} = event),
    do: event |> from_event() |> put_checkpoint(event)

  def put_checkpoint(%__MODULE__{} = run, %Jidoka.Event{data: data, loop_index: loop_index}) do
    %{
      run
      | checkpoint_token: field(data, :token) || field(data, :snapshot),
        iteration: loop_index
    }
  end

  @spec snapshot(t() | nil) :: map() | nil
  def snapshot(nil), do: nil

  def snapshot(%__MODULE__{} = run) do
    %{
      run_id: run.run_id,
      request_id: run.request_id,
      checkpoint_token: run.checkpoint_token,
      iteration: run.iteration
    }
  end

  defp field(data, key) when is_atom(key) and is_map(data) do
    Map.get(data, key, Map.get(data, Atom.to_string(key)))
  end
end
