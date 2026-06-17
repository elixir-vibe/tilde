defmodule TildeTest.Driver.Browser do
  @moduledoc "PlaywrightEx-backed browser driver for JavaScript-level Tilde behavior tests."

  import ExUnit.Assertions

  alias PlaywrightEx.{Browser, BrowserContext, Frame}

  defstruct [:browser_id, :context_id, :page_id, :frame_id, :demo, :password]

  @type t :: %__MODULE__{}
  @timeout 5_000
  @input "textarea[name='input']"

  @doc "Returns true when a local Playwright executable is available."
  @spec available?() :: boolean()
  def available?, do: not is_nil(System.find_executable("playwright"))

  @doc "Starts Playwright and a supervised Tilde demo, logs in, and visits /tilde."
  @spec open(keyword()) :: t()
  def open(opts \\ []) do
    unless available?(), do: flunk("playwright executable is not available")

    timeout = Keyword.get(opts, :timeout, @timeout)
    port = Keyword.get_lazy(opts, :port, &free_port!/0)
    ssh_port = Keyword.get_lazy(opts, :ssh_port, &free_port!/0)
    password = Keyword.get(opts, :password, "browser-test-password")

    Application.put_env(:tilde, :demo_password, password)
    configure_endpoint(port)

    {:ok, _playwright} = ensure_playwright(timeout)
    {:ok, demo} = Tilde.Demo.Supervisor.start_link(web_port: port, ssh_port: ssh_port, password: password)

    connection = PlaywrightEx.Supervisor.connection_name(TildeTest.Driver.Browser.Playwright)
    {:ok, browser} = PlaywrightEx.launch_browser(:chromium, headless: true, timeout: timeout, connection: connection)
    {:ok, context} = Browser.new_context(browser.guid, base_url: "http://127.0.0.1:#{port}", timeout: timeout, connection: connection)
    {:ok, page} = BrowserContext.new_page(context.guid, timeout: timeout, connection: connection)

    state = %__MODULE__{
      browser_id: browser.guid,
      context_id: context.guid,
      page_id: page.guid,
      frame_id: page.main_frame.guid,
      demo: demo,
      password: password
    }

    state
    |> visit("/login")
    |> fill("input[name='password']", password)
    |> click("button[type='submit']")
    |> visit("/tilde")
    |> assert_has("body .phx-connected")
  end

  @doc "Visits a path relative to the demo base URL."
  @spec visit(t(), String.t()) :: t()
  def visit(%__MODULE__{} = state, path) do
    :ok = unwrap(Frame.goto(state.frame_id, url: path, wait_until: "load", timeout: @timeout))
    state
  end

  @doc "Types into the console textarea."
  @spec type(t(), String.t()) :: t()
  def type(%__MODULE__{} = state, text) do
    :ok = unwrap(Frame.type(state.frame_id, selector: @input, text: text, timeout: @timeout))
    state
  end

  @doc "Presses a semantic key in the console textarea."
  @spec press(t(), atom()) :: t()
  def press(%__MODULE__{} = state, key) do
    :ok = unwrap(Frame.press(state.frame_id, selector: @input, key: key_name(key), timeout: @timeout))
    state
  end

  @doc "Fills an arbitrary selector."
  @spec fill(t(), String.t(), String.t()) :: t()
  def fill(%__MODULE__{} = state, selector, value) do
    :ok = unwrap(Frame.fill(state.frame_id, selector: selector, value: value, timeout: @timeout))
    state
  end

  @doc "Clicks an arbitrary selector."
  @spec click(t(), String.t()) :: t()
  def click(%__MODULE__{} = state, selector) do
    :ok = unwrap(Frame.click(state.frame_id, selector: selector, timeout: @timeout))
    state
  end

  @doc "Evaluates JavaScript in the page."
  @spec evaluate(t(), String.t()) :: any()
  def evaluate(%__MODULE__{} = state, expression) do
    unwrap(Frame.evaluate(state.frame_id, expression: expression, timeout: @timeout))
  end

  @doc "Returns visible document text."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{} = state) do
    evaluate(state, "document.body.innerText")
  end

  @doc "Asserts a selector is visible."
  @spec assert_has(t(), String.t()) :: t()
  def assert_has(%__MODULE__{} = state, selector) do
    :ok = unwrap(Frame.wait_for_selector(state.frame_id, selector: selector, timeout: @timeout))
    state
  end

  @doc "Closes browser/demo resources."
  @spec close(t()) :: :ok
  def close(%__MODULE__{} = state) do
    if state.context_id, do: BrowserContext.close(state.context_id, timeout: @timeout)
    if state.browser_id, do: Browser.close(state.browser_id, timeout: @timeout)
    if state.demo, do: GenServer.stop(state.demo)
    :ok
  end

  defp configure_endpoint(port) do
    Application.put_env(:tilde, Tilde.Demo.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      url: [scheme: "http", host: "127.0.0.1", port: port],
      check_origin: false,
      http: [ip: {127, 0, 0, 1}, port: port],
      server: true,
      code_reloader: true,
      debug_errors: true,
      secret_key_base: String.duplicate("tilde_browser_test_secret", 4),
      live_view: [signing_salt: "tilde_browser_test_salt"],
      pubsub_server: Tilde.Demo.LivePubSub,
      live_reload: [patterns: []],
      render_errors: [formats: [html: Tilde.Demo.ErrorHTML], layout: false]
    )
  end

  defp ensure_playwright(timeout) do
    case Process.whereis(TildeTest.Driver.Browser.Playwright) do
      nil ->
        PlaywrightEx.Supervisor.start_link(name: TildeTest.Driver.Browser.Playwright, timeout: timeout)

      pid ->
        {:ok, pid}
    end
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, error}), do: flunk("Playwright operation failed: #{inspect(error, pretty: true)}")

  defp key_name(:enter), do: "Enter"
  defp key_name(:tab), do: "Tab"
  defp key_name(:backtab), do: "Shift+Tab"
  defp key_name(:up), do: "ArrowUp"
  defp key_name(:down), do: "ArrowDown"
  defp key_name(:escape), do: "Escape"
  defp key_name(:ctrl_o), do: "Control+o"
  defp key_name(key), do: to_string(key)

  defp free_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_ip, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end
end
