defmodule Mix.Tasks.Marquee.CucumberTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Marquee.Cucumber

  @endpoint_config [
    http: [ip: {127, 0, 0, 1}, port: 4002],
    secret_key_base: "test-secret-key-base",
    server: true
  ]

  describe "port/1" do
    test "defaults to 4003 so the suite never collides with the ExUnit endpoint on 4002" do
      assert Cucumber.port(%{}) == 4003
      assert Cucumber.port(%{"MIX_ENV" => "test"}) == 4003
    end

    test "reads MARQUEE_CUCUMBER_PORT when it is an integer string" do
      assert Cucumber.port(%{"MARQUEE_CUCUMBER_PORT" => "4010"}) == 4010
      assert Cucumber.port(%{"MARQUEE_CUCUMBER_PORT" => "5000", "OTHER" => "x"}) == 5000
    end

    test "raises a Mix.Error naming the variable when it is not an integer" do
      for value <- ["", "abc", "40a3", "4003.5"] do
        assert_raise Mix.Error, ~r/MARQUEE_CUCUMBER_PORT/, fn ->
          Cucumber.port(%{"MARQUEE_CUCUMBER_PORT" => value})
        end
      end
    end
  end

  describe "endpoint_config/2" do
    test "replaces :http with a loopback listener on the given port" do
      config = Cucumber.endpoint_config(@endpoint_config, 4003)

      assert Keyword.fetch!(config, :http) == [ip: {127, 0, 0, 1}, port: 4003]
    end

    test "leaves every other endpoint key untouched" do
      config = Cucumber.endpoint_config(@endpoint_config, 4003)

      assert Keyword.fetch!(config, :secret_key_base) == "test-secret-key-base"
      assert Keyword.fetch!(config, :server) == true
      assert Keyword.delete(config, :http) == Keyword.delete(@endpoint_config, :http)
      assert length(config) == length(@endpoint_config)
    end

    test "adds :http when the config has none" do
      config = Cucumber.endpoint_config([server: true, secret_key_base: "s"], 4010)

      assert Keyword.fetch!(config, :http) == [ip: {127, 0, 0, 1}, port: 4010]
      assert Keyword.fetch!(config, :server) == true
      assert Keyword.fetch!(config, :secret_key_base) == "s"
      assert length(config) == 3
    end
  end

  describe "base_url/1" do
    test "points Wallaby at localhost on the given port" do
      assert Cucumber.base_url(4003) == "http://localhost:4003"
      assert Cucumber.base_url(4010) == "http://localhost:4010"
    end
  end

  describe "task registration" do
    test "mix.exs has no marquee.cucumber alias shadowing the task" do
      refute Keyword.has_key?(Mix.Project.config()[:aliases], :"marquee.cucumber")
    end

    test "mix marquee.cucumber resolves to the task module" do
      assert Mix.Task.get("marquee.cucumber") == Cucumber
    end
  end
end
