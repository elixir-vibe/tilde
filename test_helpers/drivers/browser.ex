defmodule TildeTest.Driver.Browser.JsLogger do
  @moduledoc false
  @behaviour PlaywrightEx.JsLogger

  require Logger

  @impl true
  def log(level, text, _message) when level in [:warning, :error] do
    Logger.log(level, "browser: #{inspect(text)}")
  end

  def log(_level, _text, _message), do: :ok
end

defmodule TildeTest.Driver.Browser do
  @moduledoc "PlaywrightEx-backed browser driver for JavaScript-level Tilde behavior tests."

  import ExUnit.Assertions

  alias PlaywrightEx.{Browser, BrowserContext, Frame, Page, Selector}

  defstruct [:browser_id, :context_id, :page_id, :frame_id, :connection, :demo, :password]

  @type t :: %__MODULE__{}
  @timeout 5_000
  @input "textarea[name='input']"

  @doc "Returns true when a local Playwright executable is available."
  @spec available?() :: boolean()
  def available?,
    do: File.exists?(playwright_executable()) or not is_nil(System.find_executable("playwright"))

  @doc "Starts Playwright and a supervised Tilde demo, logs in, and visits a session console."
  @spec open(keyword()) :: t()
  def open(opts \\ []) do
    unless available?(), do: flunk("playwright executable is not available")

    timeout = Keyword.get(opts, :timeout, @timeout)
    port = Keyword.get_lazy(opts, :port, &free_port!/0)
    ssh_port = Keyword.get_lazy(opts, :ssh_port, &free_port!/0)
    password = Keyword.get(opts, :password, "browser-test-password")

    Application.put_env(:tilde, :demo_password, password)
    configure_endpoint(port)
    cleanup_demo_processes()

    {:ok, _playwright} = ensure_playwright(timeout)
    {:ok, demo} = start_demo(web_port: port, ssh_port: ssh_port, password: password)

    connection = PlaywrightEx.Supervisor.connection_name(TildeTest.Driver.Browser.Playwright)

    {:ok, browser} =
      PlaywrightEx.launch_browser(:chromium,
        headless: true,
        timeout: timeout,
        connection: connection
      )

    {:ok, context} =
      Browser.new_context(browser.guid,
        base_url: "http://127.0.0.1:#{port}",
        timeout: timeout,
        connection: connection
      )

    {:ok, page} = BrowserContext.new_page(context.guid, timeout: timeout, connection: connection)

    {:ok, _subscription} =
      Page.update_subscription(page.guid,
        event: :console,
        timeout: timeout,
        connection: connection
      )

    state = %__MODULE__{
      browser_id: browser.guid,
      context_id: context.guid,
      page_id: page.guid,
      frame_id: page.main_frame.guid,
      connection: connection,
      demo: demo,
      password: password
    }

    state
    |> visit("/login")
    |> fill("input[name='password']", password)
    |> click("button[type='submit']")
    |> visit("/sessions/browser-test")
    |> assert_connected()
  end

  defp assert_connected(%__MODULE__{} = state) do
    case Frame.wait_for_selector(state.frame_id,
           selector: "body .phx-connected",
           timeout: @timeout,
           connection: state.connection
         ) do
      {:ok, _element} ->
        state

      {:error, error} ->
        diagnostics =
          evaluate(
            state,
            """
            ({
              href: location.href,
              bodyClass: document.body.className,
              liveRoots: Array.from(document.querySelectorAll('[data-phx-session]')).map(element => ({
                id: element.id,
                className: element.className
              })),
              scripts: Array.from(document.scripts).map(script => script.src),
              resources: performance.getEntriesByType('resource').map(resource => ({
                name: resource.name,
                status: resource.responseStatus
              }))
            })
            """
          )

        flunk(
          "LiveView did not connect: #{inspect(error, pretty: true)}\n" <>
            "Browser diagnostics: #{inspect(diagnostics, pretty: true)}"
        )
    end
  end

  @doc "Visits a path relative to the demo base URL."
  @spec visit(t(), String.t()) :: t()
  def visit(%__MODULE__{} = state, path) do
    unwrap(
      Frame.goto(state.frame_id,
        url: path,
        wait_until: "load",
        timeout: @timeout,
        connection: state.connection
      )
    )

    state
  end

  @doc "Types into the console textarea."
  @spec type(t(), String.t()) :: t()
  def type(%__MODULE__{} = state, text) do
    unwrap(
      Frame.type(state.frame_id,
        selector: @input,
        text: text,
        timeout: @timeout,
        connection: state.connection
      )
    )

    state
  end

  @doc "Presses a semantic key in the console textarea."
  @spec press(t(), atom()) :: t()
  def press(%__MODULE__{} = state, key) do
    press(state, @input, key)
  end

  @doc "Presses a semantic key on an arbitrary selector."
  @spec press(t(), String.t(), atom()) :: t()
  def press(%__MODULE__{} = state, selector, key) do
    unwrap(
      Frame.press(state.frame_id,
        selector: selector,
        key: key_name(key),
        timeout: @timeout,
        connection: state.connection
      )
    )

    state
  end

  @doc "Fills an arbitrary selector."
  @spec fill(t(), String.t(), String.t()) :: t()
  def fill(%__MODULE__{} = state, selector, value) do
    unwrap(
      Frame.fill(state.frame_id,
        selector: selector,
        value: value,
        timeout: @timeout,
        connection: state.connection
      )
    )

    state
  end

  @doc "Clicks an arbitrary selector."
  @spec click(t(), String.t()) :: t()
  def click(%__MODULE__{} = state, selector) do
    unwrap(
      Frame.click(state.frame_id,
        selector: selector,
        timeout: @timeout,
        connection: state.connection
      )
    )

    state
  end

  @doc "Evaluates JavaScript in the page."
  @spec evaluate(t(), String.t()) :: any()
  def evaluate(%__MODULE__{} = state, expression) do
    unwrap(
      Frame.evaluate(state.frame_id,
        expression: expression,
        timeout: @timeout,
        connection: state.connection
      )
    )
  end

  @doc "Asserts the console textarea value using Playwright's input_value API."
  @spec assert_input(t(), String.t()) :: t()
  def assert_input(%__MODULE__{} = state, value) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    assert_input(state, value, deadline)
  end

  @doc "Returns visible document text."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{} = state) do
    evaluate(state, "document.body.innerText")
  end

  @doc "Asserts a selector is visible."
  @spec assert_has(t(), String.t()) :: t()
  def assert_has(%__MODULE__{} = state, selector) do
    unwrap(
      Frame.wait_for_selector(state.frame_id,
        selector: selector,
        timeout: @timeout,
        connection: state.connection
      )
    )

    state
  end

  @doc "Waits until a selector is detached from the DOM."
  @spec refute_has(t(), String.t()) :: t()
  def refute_has(%__MODULE__{} = state, selector) do
    unwrap(
      Frame.wait_for_selector(state.frame_id,
        selector: selector,
        state: "detached",
        strict: false,
        timeout: @timeout,
        connection: state.connection
      )
    )

    state
  end

  @doc "Asserts visible text using Playwright's text selector."
  @spec assert_text(t(), String.t()) :: t()
  def assert_text(%__MODULE__{} = state, text) do
    assert_has(state, Selector.text(text))
  end

  @doc "Waits until a JavaScript expression evaluates to truthy."
  @spec wait_until(t(), String.t()) :: t()
  def wait_until(%__MODULE__{} = state, expression) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    wait_until(state, expression, deadline)
  end

  @doc "Asserts the computed CSS length for the first element matching a selector is positive."
  @spec assert_positive_css_length(t(), String.t(), String.t()) :: t()
  def assert_positive_css_length(%__MODULE__{} = state, selector, property) do
    value =
      evaluate(
        state,
        """
        (() => {
          const element = document.querySelector(#{Jason.encode!(selector)})
          if (!element) return null
          return parseFloat(getComputedStyle(element).getPropertyValue(#{Jason.encode!(property)}))
        })()
        """
      )

    assert is_number(value) and value > 0
    state
  end

  @doc "Closes browser/demo resources."
  @spec close(t()) :: :ok
  def close(%__MODULE__{} = state) do
    if state.context_id,
      do:
        ignore_exit(fn ->
          BrowserContext.close(state.context_id, timeout: @timeout, connection: state.connection)
        end)

    if state.browser_id,
      do:
        ignore_exit(fn ->
          Browser.close(state.browser_id, timeout: @timeout, connection: state.connection)
        end)

    if state.demo, do: ignore_exit(fn -> GenServer.stop(state.demo) end)
    cleanup_demo_processes()
    :ok
  end

  defp start_demo(opts) do
    case Tilde.Demo.Supervisor.start_link(opts) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        ignore_exit(fn -> GenServer.stop(pid) end)
        Tilde.Demo.Supervisor.start_link(opts)
    end
  end

  defp configure_endpoint(port) do
    Application.put_env(:tilde, :demo_code_reloader, false)

    Application.put_env(:tilde, Tilde.Demo.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      url: [scheme: "http", host: "127.0.0.1", port: port],
      check_origin: false,
      http: [ip: {127, 0, 0, 1}, port: port],
      server: true,
      code_reloader: false,
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
        case PlaywrightEx.Supervisor.start_link(
               name: TildeTest.Driver.Browser.Playwright,
               timeout: timeout,
               executable: playwright_executable(),
               js_logger: TildeTest.Driver.Browser.JsLogger
             ) do
          {:ok, pid} ->
            Process.unlink(pid)
            {:ok, pid}

          other ->
            other
        end

      pid ->
        {:ok, pid}
    end
  end

  defp playwright_executable do
    Path.expand("../../assets/node_modules/playwright/cli.js", __DIR__)
  end

  defp assert_input(state, value, deadline) do
    current =
      unwrap(
        Frame.input_value(state.frame_id,
          selector: @input,
          timeout: @timeout,
          connection: state.connection
        )
      )

    cond do
      current == value ->
        state

      System.monotonic_time(:millisecond) >= deadline ->
        assert current == value
        state

      true ->
        Process.sleep(25)
        assert_input(state, value, deadline)
    end
  end

  defp wait_until(state, expression, deadline) do
    if evaluate(state, expression) do
      state
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("Timed out waiting for browser expression: #{expression}")
      end

      Process.sleep(25)
      wait_until(state, expression, deadline)
    end
  end

  defp cleanup_demo_processes do
    Tilde.Session.Supervisor.stop_sessions()

    [Tilde.Demo.LivePubSub, Tilde.Runtime.RateLimit]
    |> Enum.each(fn name ->
      if pid = Process.whereis(name) do
        ignore_exit(fn -> GenServer.stop(pid) end)
      end
    end)
  end

  defp ignore_exit(fun) do
    fun.()
  catch
    :exit, _reason -> :ok
  end

  defp unwrap({:ok, value}), do: value

  defp unwrap({:error, error}),
    do: flunk("Playwright operation failed: #{inspect(error, pretty: true)}")

  defp key_name(:enter), do: "Enter"
  defp key_name(:tab), do: "Tab"
  defp key_name(:backtab), do: "Shift+Tab"
  defp key_name(:up), do: "ArrowUp"
  defp key_name(:down), do: "ArrowDown"
  defp key_name(:escape), do: "Escape"
  defp key_name(:ctrl_o), do: "Control+O"
  defp key_name(:ctrl_p), do: "Control+P"
  defp key_name(key), do: to_string(key)

  defp free_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_ip, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end
end
