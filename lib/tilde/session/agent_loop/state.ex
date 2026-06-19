defmodule Tilde.Session.AgentLoop.State do
  @moduledoc "Typed runtime state for the session-owned agent loop."

  alias Tilde.Core.AgentRuntime
  alias Tilde.Session.AgentLoop.{Prompt, ResumeCandidate, Run}

  defstruct active?: false,
            input_index: nil,
            task: nil,
            ref: nil,
            block_id: nil,
            run: nil,
            queue: []

  @type t :: %__MODULE__{
          active?: boolean(),
          input_index: pos_integer() | nil,
          task: pid() | nil,
          ref: reference() | nil,
          block_id: String.t() | nil,
          run: Run.t() | nil,
          queue: [Prompt.t()]
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{active?: active?}), do: active?

  @spec matches_ref?(t(), reference()) :: boolean()
  def matches_ref?(%__MODULE__{ref: ref}, ref), do: true
  def matches_ref?(%__MODULE__{}, _ref), do: false

  @spec start(t(), Prompt.t(), pid(), reference(), String.t()) :: t()
  def start(%__MODULE__{} = state, %Prompt{} = prompt, task, ref, block_id) when is_pid(task) do
    %{
      state
      | active?: true,
        input_index: prompt.index,
        task: task,
        ref: ref,
        block_id: block_id,
        run: nil
    }
  end

  @spec resume(t(), ResumeCandidate.t(), pid(), reference(), String.t()) :: t()
  def resume(%__MODULE__{} = state, %ResumeCandidate{} = candidate, task, ref, block_id)
      when is_pid(task) do
    %{
      state
      | active?: true,
        input_index: candidate.input_index,
        task: task,
        ref: ref,
        block_id: block_id,
        run: Run.from_resume_candidate(candidate)
    }
  end

  @spec clear_active(t()) :: t()
  def clear_active(%__MODULE__{} = state) do
    %{state | active?: false, input_index: nil, task: nil, ref: nil, block_id: nil, run: nil}
  end

  @spec put_run(t(), Run.t() | nil) :: t()
  def put_run(%__MODULE__{} = state, run), do: %{state | run: run}

  @spec put_checkpoint(t(), Jido.AI.Runtime.Event.t()) :: t()
  def put_checkpoint(%__MODULE__{} = state, event) do
    %{state | run: Run.put_checkpoint(state.run, event)}
  end

  @spec enqueue(t(), Prompt.t()) :: t()
  def enqueue(%__MODULE__{} = state, %Prompt{} = prompt) do
    %{state | queue: dedupe_append(state.queue, prompt)}
  end

  @spec pop_queue(t()) :: {Prompt.t() | nil, t()}
  def pop_queue(%__MODULE__{queue: [prompt | rest]} = state), do: {prompt, %{state | queue: rest}}
  def pop_queue(%__MODULE__{} = state), do: {nil, state}

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = state) do
    state
    |> durable_snapshot()
    |> Map.put(:task_alive?, alive?(state.task))
  end

  @spec durable_snapshot(t()) :: map()
  def durable_snapshot(%__MODULE__{} = state) do
    state
    |> runtime()
    |> AgentRuntime.dump()
  end

  @spec runtime(t()) :: AgentRuntime.t()
  def runtime(%__MODULE__{} = state) do
    AgentRuntime.from_agent_loop(%{
      active?: state.active?,
      input_index: state.input_index,
      block_id: state.block_id,
      queue_length: length(state.queue),
      run: Run.snapshot(state.run)
    })
  end

  defp alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp alive?(_pid), do: false

  defp dedupe_append(prompts, %Prompt{index: index} = prompt) do
    if Enum.any?(prompts, &(&1.index == index)) do
      prompts
    else
      prompts ++ [prompt]
    end
  end
end
