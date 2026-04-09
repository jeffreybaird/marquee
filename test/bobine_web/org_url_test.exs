defmodule BobineWeb.OrgURLTest do
  # Not async — toggles Application env (`:bobine, :org_resolution`).
  use ExUnit.Case, async: false

  alias BobineWeb.OrgURL

  doctest BobineWeb.OrgURL

  setup do
    original = Application.get_env(:bobine, :org_resolution)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:bobine, :org_resolution)
      else
        Application.put_env(:bobine, :org_resolution, original)
      end
    end)

    :ok
  end

  describe "org_url/2 (reads :org_resolution from config)" do
    test "appends ?org=slug when config is :query_param" do
      Application.put_env(:bobine, :org_resolution, :query_param)

      assert OrgURL.org_url("https://app.example.com/admin", %{slug: "demo"}) ==
               "https://app.example.com/admin?org=demo"
    end

    test "passes through when config is :hostname" do
      Application.put_env(:bobine, :org_resolution, :hostname)

      assert OrgURL.org_url("https://demo.example.com/admin", %{slug: "demo"}) ==
               "https://demo.example.com/admin"
    end

    test "defaults to :query_param when config is unset" do
      Application.delete_env(:bobine, :org_resolution)

      assert OrgURL.org_url("https://app.example.com/", %{slug: "demo"}) ==
               "https://app.example.com/?org=demo"
    end
  end

  describe "org_url/3 (explicit mode)" do
    test "appends ?org=slug to a URL with no existing query string" do
      assert OrgURL.org_url("https://app.example.com/admin", %{slug: "demo"}, :query_param) ==
               "https://app.example.com/admin?org=demo"
    end

    test "appends ?org=slug to a URL that already has query params" do
      result =
        OrgURL.org_url(
          "https://app.example.com/checkout?session_id=abc&ref=email",
          %{slug: "demo"},
          :query_param
        )

      uri = URI.parse(result)
      query = URI.decode_query(uri.query)

      assert query["org"] == "demo"
      assert query["session_id"] == "abc"
      assert query["ref"] == "email"
      assert uri.path == "/checkout"
    end

    test "overwrites a stale org param when one is already present" do
      result =
        OrgURL.org_url(
          "https://app.example.com/admin?org=stale&keep=me",
          %{slug: "demo"},
          :query_param
        )

      uri = URI.parse(result)
      query = URI.decode_query(uri.query)

      assert query["org"] == "demo"
      assert query["keep"] == "me"
    end

    test "preserves the URL fragment" do
      result =
        OrgURL.org_url(
          "https://app.example.com/admin#section",
          %{slug: "demo"},
          :query_param
        )

      uri = URI.parse(result)
      assert uri.fragment == "section"
      assert URI.decode_query(uri.query)["org"] == "demo"
    end

    test "passes the URL through unchanged in :hostname mode" do
      assert OrgURL.org_url(
               "https://demo.example.com/admin?ref=email",
               %{slug: "demo"},
               :hostname
             ) == "https://demo.example.com/admin?ref=email"
    end

    test "works with a full %Organization{} struct" do
      org = %Bobine.Accounts.Organization{slug: "demo"}

      assert OrgURL.org_url("https://app.example.com/", org, :query_param) ==
               "https://app.example.com/?org=demo"
    end
  end
end
