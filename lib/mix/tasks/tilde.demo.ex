defmodule Mix.Tasks.Tilde.Demo do
  @moduledoc """
  Runs the mirrored Tilde LiveView + SSH demo.

      mix tilde.demo
      mix tilde.demo --web-port 4000 --ssh-port 4022

  Open the LiveView at <http://localhost:4000/tilde> and connect over SSH:

      ssh tilde@localhost -p 4022 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null

  Password: `tilde`.
  """

  use Mix.Task

  @shortdoc "Runs the mirrored Tilde LiveView + SSH demo"

  @switches [web_port: :integer, ssh_port: :integer, password: :string]
  @aliases [w: :web_port, s: :ssh_port, p: :password]

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args, _invalid} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)
    web_port = Keyword.get(opts, :web_port, 4000)
    ssh_port = Keyword.get(opts, :ssh_port, 4022)
    password = Keyword.get(opts, :password, "tilde")

    configure_endpoint(web_port)
    start_pubsub()
    start_session_server()
    start_endpoint()
    start_ssh(ssh_port, password)

    Mix.shell().info("""

    Tilde mirrored demo is running.

      LiveView: http://localhost:#{web_port}/tilde
      SSH:      ssh tilde@localhost -p #{ssh_port} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      Password: #{password}

    Both renderers share Tilde.SessionServer.
    Press Ctrl+C twice to stop.
    """)

    Process.sleep(:infinity)
  end

  defp configure_endpoint(web_port) do
    Application.put_env(:tilde, Tilde.Live.DemoEndpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: web_port],
      server: true,
      secret_key_base: String.duplicate("tilde_demo_secret", 5),
      live_view: [signing_salt: "tilde_demo_salt"],
      pubsub_server: Tilde.Live.DemoPubSub,
      render_errors: [formats: [html: Tilde.Live.DemoErrorHTML], layout: false]
    )
  end

  defp start_pubsub do
    case Process.whereis(Tilde.Live.DemoPubSub) do
      nil ->
        Supervisor.start_link([{Phoenix.PubSub, name: Tilde.Live.DemoPubSub}],
          strategy: :one_for_one
        )

      pid ->
        {:ok, pid}
    end
  end

  defp start_session_server do
    Tilde.SessionServer.ensure_started(Tilde.SessionServer,
      session: Tilde.Live.Demo.demo_session()
    )
  end

  defp start_endpoint do
    case Process.whereis(Tilde.Live.DemoEndpoint) do
      nil -> Tilde.Live.DemoEndpoint.start_link()
      pid -> {:ok, pid}
    end
  end

  defp start_ssh(ssh_port, password) do
    Tilde.SSH.Demo.start_link(
      port: ssh_port,
      password: password,
      session_server: Tilde.SessionServer
    )
  end
end
