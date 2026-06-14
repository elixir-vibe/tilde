defmodule Tilde.Agent do
  @moduledoc """
  Minimal Jido AI agent for Tilde demos.

  Tilde keeps session/transcript semantics in its own event model, then uses this
  Jido agent as the model/tool runtime boundary. Tool modules can be added here
  without changing LiveView, SSH, or TUI renderers.
  """

  if Code.ensure_loaded?(Jido.AI.Agent) do
    use Jido.AI.Agent,
      name: "tilde_agent",
      description: "Small shared-session assistant for Tilde demos",
      model: :tilde_haiku,
      tools: [],
      max_iterations: 4,
      max_tokens: 800,
      streaming: false,
      system_prompt: """
      You are Tilde, a concise assistant running inside a shared semantic console.
      Respond briefly. Do not claim to run tools unless a tool is actually available.
      """
  end
end
