defmodule Mix.Tasks.Marquee.Cucumber do
  @shortdoc "Runs the whole features/** Cucumberex suite in a browser on its own port"

  @moduledoc """
  Runs the full Wallaby-backed Cucumberex suite (every `.feature` under
  `features/`) with the endpoint bound to its own port, so it can run next to
  `mix test`.

  `config/test.exs` starts the endpoint on port 4002 and points Wallaby at
  `http://localhost:4002`, which is what `mix test --only e2e` uses. Plain
  `mix cucumber` reuses that configuration, so it cannot run while `mix test`
  holds the port. This task rebinds the endpoint and Wallaby to
  `MARQUEE_CUCUMBER_PORT` (default 4003) before delegating to `mix cucumber`.

  Every scenario starts a Wallaby browser session, so Chrome and a matching
  ChromeDriver must be installed. `MIX_ENV=test` is set automatically through
  `preferred_envs` in `mix.exs`.

  ## Usage

      mix marquee.cucumber [cucumber options] [feature files]
      MARQUEE_CUCUMBER_PORT=4010 mix marquee.cucumber --format pretty --strict

  All arguments are forwarded to `mix cucumber` verbatim.

  ## Examples

      mix marquee.cucumber
      mix marquee.cucumber --format pretty --strict features/authentication.feature
      mix marquee.cucumber --tags @smoke
  """

  use Mix.Task

  @port_env "MARQUEE_CUCUMBER_PORT"
  @default_port 4003

  @impl Mix.Task
  def run(args) do
    port = port(System.get_env())

    Application.put_env(
      :marquee,
      MarqueeWeb.Endpoint,
      endpoint_config(Application.get_env(:marquee, MarqueeWeb.Endpoint, []), port)
    )

    Application.put_env(:wallaby, :base_url, base_url(port))

    Mix.Task.run("cucumber", args)
  end

  @doc """
  Returns the port the suite should listen on, read from `MARQUEE_CUCUMBER_PORT`
  in `env` and defaulting to #{@default_port}.

      iex> Mix.Tasks.Marquee.Cucumber.port(%{"MARQUEE_CUCUMBER_PORT" => "4010"})
      4010

      iex> Mix.Tasks.Marquee.Cucumber.port(%{})
      4003

  Raises `Mix.Error` when the variable is set to anything but an integer.
  """
  @spec port(%{optional(String.t()) => String.t()}) :: pos_integer()
  def port(env) do
    case Map.fetch(env, @port_env) do
      :error -> @default_port
      {:ok, value} -> parse_port(value)
    end
  end

  @doc """
  Returns `config` with `:http` set to a loopback listener on `port`; every
  other key is left untouched.

      iex> Mix.Tasks.Marquee.Cucumber.endpoint_config([http: [port: 4002], server: true], 4003)
      [http: [ip: {127, 0, 0, 1}, port: 4003], server: true]

      iex> Mix.Tasks.Marquee.Cucumber.endpoint_config([server: true], 4010)
      [http: [ip: {127, 0, 0, 1}, port: 4010], server: true]
  """
  @spec endpoint_config(keyword(), pos_integer()) :: keyword()
  def endpoint_config(config, port) do
    config
    |> Keyword.delete(:http)
    |> Keyword.put(:http, ip: {127, 0, 0, 1}, port: port)
  end

  @doc """
  Returns the Wallaby base URL for a suite listening on `port`.

      iex> Mix.Tasks.Marquee.Cucumber.base_url(4003)
      "http://localhost:4003"
  """
  @spec base_url(pos_integer()) :: String.t()
  def base_url(port), do: "http://localhost:#{port}"

  defp parse_port(value) do
    case Integer.parse(value) do
      {port, ""} -> port
      _other -> Mix.raise("#{@port_env} must be an integer port number, got: #{inspect(value)}")
    end
  end
end
