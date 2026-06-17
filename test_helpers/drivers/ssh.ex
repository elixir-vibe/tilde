defmodule TildeTest.Driver.SSH do
  @moduledoc "Real SSH daemon driver for transport integration behavior tests."

  @behaviour TildeTest.Driver

  alias Tilde.Session.Server, as: SessionServer

  defstruct [:connection, :channel, :server, :daemon, :system_dir, output: ""]

  @type t :: %__MODULE__{}

  @password "test-password"
  @timeout 5_000

  @impl true
  def open(opts \\ []) do
    session = Keyword.get_lazy(opts, :session, &Tilde.session/0)
    port = Keyword.get_lazy(opts, :port, &free_port!/0)
    system_dir = Path.join(System.tmp_dir!(), "tilde-ssh-driver-#{System.unique_integer([:positive])}")
    server = {:global, {:tilde_ssh_driver, System.unique_integer([:positive])}}

    {:ok, _registry} = Tilde.Session.Registry.ensure_started()
    {:ok, _server} = SessionServer.ensure_started(server, session: session)

    {:ok, daemon} =
      Tilde.Transport.SSH.Demo.start_link(
        port: port,
        password: @password,
        system_dir: system_dir,
        session_server: server,
        session_mode: :shared
      )

    {:ok, connection} =
      :ssh.connect(~c"localhost", port,
        user: ~c"shared",
        password: String.to_charlist(@password),
        user_interaction: false,
        silently_accept_hosts: true
      )

    {:ok, channel} = :ssh_connection.session_channel(connection, @timeout)
    :success = :ssh_connection.ptty_alloc(connection, channel, [])
    :ok = :ssh_connection.shell(connection, channel)

    %__MODULE__{
      connection: connection,
      channel: channel,
      server: server,
      daemon: daemon,
      system_dir: system_dir
    }
    |> collect()
  end

  @impl true
  def type(%__MODULE__{} = state, text) when is_binary(text) do
    Enum.reduce(String.graphemes(text), state, fn grapheme, state ->
      press(state, {:text, grapheme})
    end)
  end

  @impl true
  def press(%__MODULE__{} = state, key) do
    :ok = :ssh_connection.send(state.connection, state.channel, 0, key_bytes(key), @timeout)
    collect(state)
  end

  @impl true
  def text(%__MODULE__{output: output}), do: strip_ansi(output)

  @impl true
  def session(%__MODULE__{server: server}), do: SessionServer.get_session(server)

  @doc "Closes the SSH driver and removes generated host keys."
  @spec close(t()) :: :ok
  def close(%__MODULE__{} = state) do
    if state.connection, do: :ssh.close(state.connection)
    if state.daemon, do: GenServer.stop(state.daemon)
    if state.system_dir, do: File.rm_rf!(state.system_dir)
    :ok
  end

  defp collect(%__MODULE__{} = state) do
    %{state | output: state.output <> collect_output("")}
  end

  defp collect_output(acc) do
    receive do
      {:ssh_cm, _connection, {:data, _channel, _type, data}} -> collect_output(acc <> data)
      {:ssh_cm, _connection, {:exit_status, _channel, _status}} -> collect_output(acc)
      {:ssh_cm, _connection, {:eof, _channel}} -> collect_output(acc)
      {:ssh_cm, _connection, {:closed, _channel}} -> acc
    after
      100 -> acc
    end
  end

  defp key_bytes({:text, text}), do: text
  defp key_bytes(:enter), do: "\r"
  defp key_bytes(:tab), do: "\t"
  defp key_bytes(:backtab), do: "\e[Z"
  defp key_bytes(:up), do: "\e[A"
  defp key_bytes(:down), do: "\e[B"
  defp key_bytes(:escape), do: <<27>>
  defp key_bytes(:ctrl_o), do: <<15>>
  defp key_bytes(:interrupt), do: <<3>>
  defp key_bytes(:backspace), do: <<127>>

  defp free_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_ip, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
end
