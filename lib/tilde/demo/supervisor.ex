defmodule Tilde.Demo.Supervisor do
  @moduledoc "Supervision tree for the standalone LiveView + SSH demo."

  use Supervisor

  @doc "Starts the demo supervision tree."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    ssh_port = Keyword.fetch!(opts, :ssh_port)
    password = Keyword.fetch!(opts, :password)

    children = [
      {Tilde.Runtime.RateLimit, clean_period: :timer.minutes(1)},
      {Phoenix.PubSub, name: Tilde.Demo.LivePubSub},
      {Registry, keys: :unique, name: Tilde.Session.Registry},
      {Tilde.Session.Server, name: Tilde.Session.Server, session: Tilde.Demo.Live.demo_session()},
      Tilde.Demo.Endpoint,
      {Tilde.Transport.SSH.Demo, port: ssh_port, password: password, session_mode: :private}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
