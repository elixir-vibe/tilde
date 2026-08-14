defmodule Tilde.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Tilde.Session.Supervisor]
    Supervisor.start_link(children, strategy: :one_for_one, name: Tilde.Supervisor)
  end
end
