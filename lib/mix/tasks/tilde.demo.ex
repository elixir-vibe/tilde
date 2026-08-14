defmodule Mix.Tasks.Tilde.Demo do
  @moduledoc """
  Runs the mirrored Tilde LiveView + SSH demo.

      mix tilde.demo
      mix tilde.demo --web-port 4000 --ssh-port 4022

  Open the LiveView at <http://localhost:4000/> and connect over SSH:

      ssh tilde@localhost -p 4022 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null

  Password: #{Tilde.Demo.Password.help()}.
  """

  use Mix.Task

  @shortdoc "Runs the mirrored Tilde LiveView + SSH demo"

  @switches [
    web_port: :integer,
    ssh_port: :integer,
    password: :string,
    host: :string,
    hmr: :boolean
  ]
  @aliases [w: :web_port, s: :ssh_port, p: :password, h: :host]

  @impl true
  def run(argv) do
    :ok = Tilde.Demo.Environment.load()

    Mix.Task.run("app.start")

    {opts, _args, _invalid} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)
    web_port = Keyword.get(opts, :web_port, 4000)
    ssh_port = Keyword.get(opts, :ssh_port, 4022)
    password = Tilde.Demo.Password.configure(opts)
    host = Keyword.get(opts, :host, "localhost")
    hmr? = Keyword.get(opts, :hmr, true)

    configure_llm()
    configure_endpoint(web_port, host, hmr?)
    start_demo_supervisor(ssh_port, password)

    Mix.shell().info("""

    Tilde mirrored demo is running.

      LiveView: http://localhost:#{web_port}/
      SSH:      ssh tilde@localhost -p #{ssh_port} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      Password: #{password}
      HMR:      #{if hmr?, do: "enabled", else: "disabled"}

    SSH tilde@... opens a private session. SSH shared@... or name@... attaches a named session.
    Web /sessions/:session_id attaches the same named session.
    Press Ctrl+C twice to stop.
    """)

    Process.sleep(:infinity)
  end

  defp configure_llm do
    Application.put_env(:tilde, :llm_enabled, true)

    Application.put_env(:tilde, :llm_rate_limit,
      scope: :session,
      scale: :timer.seconds(30),
      limit: 3
    )
  end

  defp configure_endpoint(web_port, host, hmr?) do
    Application.put_env(:tilde, :demo_code_reloader, true)

    Application.put_env(:tilde, Tilde.Demo.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      url: [scheme: "https", host: host, port: 443],
      check_origin: ["https://#{host}"],
      http: [ip: {127, 0, 0, 1}, port: web_port],
      server: true,
      code_reloader: true,
      debug_errors: true,
      secret_key_base: String.duplicate("tilde_demo_secret", 5),
      live_view: [signing_salt: "tilde_demo_salt"],
      pubsub_server: Tilde.Demo.LivePubSub,
      live_reload: live_reload_config(hmr?),
      render_errors: [formats: [html: Tilde.Demo.ErrorHTML], layout: false]
    )
  end

  defp live_reload_config(false), do: [patterns: []]

  defp live_reload_config(true) do
    [
      web_console_logger: true,
      patterns: [
        ~r"lib/tilde/(demo|transport/live|core|tool|view).*\\.(ex)$",
        ~r"lib/mix/tasks/tilde\\.demo\\.ex$",
        ~r"README\\.md$",
        ~r"docs/.*\\.md$"
      ]
    ]
  end

  defp start_demo_supervisor(ssh_port, password) do
    case Tilde.Demo.Supervisor.start_link(ssh_port: ssh_port, password: password) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end
end
