defmodule Marquee.DemoContentReleaseBootTest do
  use ExUnit.Case, async: false
  @moduletag :tmp_dir

  test "release eval provisions without starting the full application or background workers", %{
    tmp_dir: dir
  } do
    config_path = Path.join(dir, "release-config.etf")
    File.write!(config_path, :erlang.term_to_binary(Application.get_all_env(:marquee)))

    script = """
    Application.load(:marquee)
    config = File.read!(hd(System.argv())) |> :erlang.binary_to_term()
    Enum.each(config, fn {key, value} -> Application.put_env(:marquee, key, value) end)
    forbidden = [Marquee.Supervisor, MarqueeWeb.Endpoint, Oban]
    Enum.each(forbidden, fn name ->
      if Process.whereis(name), do: raise("unexpected worker before release eval")
    end)
    case Marquee.Release.seed_missing_demo_content() do
      {:ok, _} -> :ok
      other -> raise("release provisioning failed: \#{inspect(other)}")
    end
    Enum.each(forbidden, fn name ->
      if Process.whereis(name), do: raise("release eval started forbidden worker")
    end)
    if Enum.any?(Application.started_applications(), fn {app, _, _} -> app == :marquee end),
      do: raise("release eval booted full marquee application")
    IO.puts("PARTIAL_RELEASE_BOOT_OK")
    """

    paths = :code.get_path() |> Enum.flat_map(fn path -> ["-pa", List.to_string(path)] end)

    assert {output, 0} =
             System.cmd(
               System.find_executable("elixir"),
               paths ++ ["-e", script, "--", config_path],
               stderr_to_stdout: true
             )

    assert output =~ "PARTIAL_RELEASE_BOOT_OK"
  end
end
