defmodule Tilde.RateLimit do
  @moduledoc """
  Optional Hammer-backed rate limiting for public demos.

  Tilde's core does not require Hammer. When Hammer is available, this module
  uses the ETS backend; otherwise all checks are allowed.
  """

  if Code.ensure_loaded?(Hammer) do
    use Hammer, backend: :ets

    @doc "Ensures the Hammer ETS rate limiter is running."
    @spec ensure_started(keyword()) :: {:ok, pid()} | {:error, term()}
    def ensure_started(opts \\ []) do
      case Process.whereis(__MODULE__) do
        nil -> start_link(opts)
        pid -> {:ok, pid}
      end
    end

    @doc "Checks a rate limit using Hammer."
    @spec check(String.t(), pos_integer(), pos_integer()) ::
            {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
    def check(key, scale, limit), do: hit(key, scale, limit)
  else
    @doc "No-op fallback when Hammer is not installed."
    @spec ensure_started(keyword()) :: {:ok, pid()}
    def ensure_started(_opts \\ []), do: {:ok, self()}

    @doc "Allows all events when Hammer is not installed."
    @spec check(String.t(), pos_integer(), pos_integer()) :: {:allow, non_neg_integer()}
    def check(_key, _scale, _limit), do: {:allow, 0}
  end

  @doc "Checks the configured LLM/demo rate limit."
  @spec check_llm(Tilde.Session.t()) :: :ok | {:error, {:rate_limited, non_neg_integer()}}
  def check_llm(session) do
    case Application.get_env(:tilde, :llm_rate_limit, false) do
      false ->
        :ok

      opts when is_list(opts) ->
        key = llm_key(session, opts)
        scale = Keyword.get(opts, :scale, :timer.seconds(30))
        limit = Keyword.get(opts, :limit, 3)

        case check(key, scale, limit) do
          {:allow, _count} -> :ok
          {:deny, retry_after} -> {:error, {:rate_limited, retry_after}}
        end
    end
  end

  defp llm_key(session, opts) do
    prefix = Keyword.get(opts, :prefix, "tilde:llm")

    case Keyword.get(opts, :scope, :global) do
      :session -> "#{prefix}:#{session.id}"
      :global -> "#{prefix}:global"
      other -> "#{prefix}:#{other}"
    end
  end
end
