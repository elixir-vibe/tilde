defmodule Tilde.Session.AgentLoop.State do
  @moduledoc "Typed runtime state for the session-owned agent loop."

  alias Tilde.Core.AgentRuntime
  alias Tilde.Session.AgentLoop.Prompt

  defstruct active?: false,
            input_index: nil,
            task: nil,
            ref: nil,
            timeout_timer: nil,
            block_id: nil,
            runtime: nil,
            queue: []

  @type t :: %__MODULE__{
          active?: boolean(),
          input_index: pos_integer() | nil,
          task: pid() | nil,
          ref: reference() | nil,
          timeout_timer: reference() | nil,
          block_id: String.t() | nil,
          runtime: AgentRuntime.t() | nil,
          queue: [Prompt.t()]
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{active?: active?}), do: active?

  @spec matches_ref?(t(), reference()) :: boolean()
  def matches_ref?(%__MODULE__{ref: ref}, ref), do: true
  def matches_ref?(%__MODULE__{}, _ref), do: false

  @spec matches_task?(t(), pid(), reference() | nil) :: boolean()
  def matches_task?(state, task, ref \\ nil)

  def matches_task?(%__MODULE__{active?: true, task: task, ref: ref}, task, ref)
      when is_pid(task),
      do: true

  def matches_task?(%__MODULE__{active?: true, task: task}, task, nil) when is_pid(task), do: true
  def matches_task?(%__MODULE__{}, _task, _ref), do: false

  @spec start(t(), Prompt.t(), pid(), reference(), reference() | nil, String.t()) :: t()
  def start(%__MODULE__{} = state, %Prompt{} = prompt, task, ref, timeout_timer, block_id)
      when is_pid(task) do
    %{
      state
      | active?: true,
        input_index: prompt.index,
        task: task,
        ref: ref,
        timeout_timer: timeout_timer,
        block_id: block_id,
        runtime: nil
    }
  end

  @spec resume(t(), AgentRuntime.t(), pid(), reference(), reference() | nil, String.t()) :: t()
  def resume(%__MODULE__{} = state, %AgentRuntime{} = runtime, task, ref, timeout_timer, block_id)
      when is_pid(task) do
    %{
      state
      | active?: true,
        input_index: runtime.input_index,
        task: task,
        ref: ref,
        timeout_timer: timeout_timer,
        block_id: block_id,
        runtime: runtime
    }
  end

  @spec task_stopped(t()) :: t()
  def task_stopped(%__MODULE__{} = state), do: %{state | task: nil, timeout_timer: nil}

  @spec clear_active(t()) :: t()
  def clear_active(%__MODULE__{} = state) do
    %{
      state
      | active?: false,
        input_index: nil,
        task: nil,
        ref: nil,
        timeout_timer: nil,
        block_id: nil,
        runtime: nil
    }
  end

  @spec put_started_runtime(t(), Jidoka.Event.t()) :: t()
  def put_started_runtime(%__MODULE__{} = state, %Jidoka.Event{} = event) do
    %{state | runtime: runtime_from_event(event)}
  end

  @spec put_checkpoint(t(), Jidoka.Event.t()) :: t()
  def put_checkpoint(%__MODULE__{} = state, %Jidoka.Event{} = event) do
    %{state | runtime: checkpoint_runtime(state.runtime, event)}
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
    AgentRuntime.new(%{
      active?: state.active?,
      input_index: state.input_index,
      block_id: state.block_id,
      queue_length: length(state.queue),
      run_id: runtime_field(state.runtime, :run_id),
      request_id: runtime_field(state.runtime, :request_id),
      checkpoint_token: runtime_field(state.runtime, :checkpoint_token),
      iteration: runtime_field(state.runtime, :iteration)
    })
  end

  defp checkpoint_runtime(nil, %Jidoka.Event{} = event) do
    event
    |> runtime_from_event()
    |> checkpoint_runtime(event)
  end

  defp checkpoint_runtime(%AgentRuntime{} = runtime, %Jidoka.Event{
         data: data,
         loop_index: loop_index
       }) do
    %{
      runtime
      | checkpoint_token: field(data, :token) || field(data, :snapshot),
        iteration: loop_index
    }
  end

  defp runtime_from_event(%Jidoka.Event{} = event) do
    AgentRuntime.new(
      active?: true,
      run_id: event.agent_id || event.request_id || event.effect_id,
      request_id: event.request_id,
      iteration: event.loop_index
    )
  end

  defp runtime_field(%AgentRuntime{} = runtime, field), do: Map.get(runtime, field)
  defp runtime_field(nil, _field), do: nil

  defp field(data, key) when is_atom(key) and is_map(data) do
    Map.get(data, key, Map.get(data, Atom.to_string(key)))
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
