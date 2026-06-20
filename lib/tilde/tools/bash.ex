defmodule Tilde.Tools.Bash do
  @moduledoc "Model-facing bash execution tool."

  import JSONSpec

  alias Tilde.Tool.Output

  @schema schema(
            %{
              required(:command) => String.t(),
              optional(:timeout) => pos_integer()
            },
            doc: [command: "Bash command to execute", timeout: "Timeout in seconds"]
          )

  use Jido.Action,
    name: "bash",
    description:
      "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to the last 2000 lines or 50KB. Optionally provide a timeout in seconds.",
    category: "shell",
    tags: ["shell"],
    schema: @schema

  @impl true
  def run(params, _context) do
    params = JSONSpec.atomize(@schema, params)
    started_at = System.monotonic_time(:millisecond)

    case run_command(params.command, params[:timeout]) do
      {:ok, output, exit_code} ->
        duration_ms = System.monotonic_time(:millisecond) - started_at
        {content, truncation} = Output.truncate_tail(output)

        {:ok,
         %{
           content: [Output.text_part(content)],
           details: %{truncation: truncation},
           exit_code: exit_code,
           duration_ms: duration_ms
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_command(command, timeout) when is_binary(command) do
    opts = [stderr_to_stdout: true, cd: File.cwd!()] ++ timeout_opts(timeout)

    try do
      {output, exit_code} = System.cmd("bash", ["-c", command], opts)
      {:ok, output, exit_code}
    rescue
      error in [ErlangError, ArgumentError] -> {:error, Exception.message(error)}
    catch
      :exit, reason -> {:error, inspect(reason)}
    end
  end

  defp run_command(_command, _timeout), do: {:error, "command must be a string"}

  defp timeout_opts(timeout) when is_integer(timeout) and timeout > 0,
    do: [timeout: timeout * 1_000]

  defp timeout_opts(_timeout), do: []
end
