defmodule Tilde.SSH.Demo do
  @moduledoc """
  SSH server for the Tilde TUI demo.

  Start it from `iex -S mix`:

      {:ok, _pid} = Tilde.SSH.Demo.start_link(port: 4022)

  Then connect with OpenSSH:

      ssh tilde@localhost -p 4022 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null

  Password: `tilde`
  """

  use GenServer

  alias Tilde.SSH.Keys

  @default_port 4022
  @default_password "tilde"

  @type option :: {:port, :inet.port_number()} | {:system_dir, Path.t()} | {:password, String.t()}

  @doc "Starts the demo SSH daemon under a GenServer."
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Returns the daemon reference."
  @spec daemon_ref(GenServer.server()) :: term()
  def daemon_ref(server), do: GenServer.call(server, :daemon_ref)

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    password = Keyword.get(opts, :password, @default_password)
    system_dir = Keyword.get_lazy(opts, :system_dir, &default_system_dir/0)

    with {:ok, _apps} <- :application.ensure_all_started(:ssh),
         {:ok, system_dir} <- Keys.ensure_system_dir(system_dir),
         {:ok, daemon_ref} <- start_daemon(port, system_dir, password) do
      {:ok, %{daemon_ref: daemon_ref, port: port, system_dir: system_dir}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:daemon_ref, _from, state), do: {:reply, state.daemon_ref, state}

  @impl true
  def terminate(_reason, %{daemon_ref: daemon_ref}) do
    :ssh.stop_daemon(daemon_ref)
  end

  def terminate(_reason, _state), do: :ok

  defp start_daemon(port, system_dir, password) do
    :ssh.daemon(port, [
      {:system_dir, String.to_charlist(system_dir)},
      {:auth_methods, ~c"password"},
      {:pwdfun, password_fun(password)},
      {:ssh_cli, {Tilde.SSH.Channel, [[width: 100]]}},
      {:parallel_login, true}
    ])
  end

  defp password_fun(password) do
    password_chars = String.to_charlist(password)
    fn _user, supplied_password -> supplied_password == password_chars end
  end

  defp default_system_dir do
    Path.expand("_build/tilde_ssh/system")
  end
end
