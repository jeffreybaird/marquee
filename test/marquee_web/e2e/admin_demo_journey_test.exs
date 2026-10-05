defmodule MarqueeWeb.E2E.AdminDemoJourneyTest do
  use MarqueeWeb.WallabyCase

  import Ecto.Query
  alias Marquee.{AdminDemo, Branding, Repo}

  alias Marquee.Accounts.Organization
  alias Marquee.AdminDemo.Session
  alias Marquee.Content.Video
  alias Phoenix.Ecto.SQL.Sandbox

  @moduletag :e2e
  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "travel.json")
    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))
    host = "demo.localhost"
    original = Application.fetch_env(:marquee, :admin_demo)
    endpoint_config = Application.fetch_env!(:marquee, MarqueeWeb.Endpoint)

    Application.put_env(
      :marquee,
      MarqueeWeb.Endpoint,
      Keyword.put(endpoint_config, :check_origin, :conn)
    )

    MarqueeWeb.Endpoint.config_change(
      [{MarqueeWeb.Endpoint, Keyword.put(endpoint_config, :check_origin, :conn)}],
      []
    )

    Application.put_env(:marquee, :admin_demo, enabled: true, host: host, catalog_path: path)

    on_exit(fn ->
      Application.put_env(:marquee, MarqueeWeb.Endpoint, endpoint_config)
      MarqueeWeb.Endpoint.config_change([{MarqueeWeb.Endpoint, endpoint_config}], [])

      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end)

    {:ok, _} = AdminDemo.configure_host(host)
    :ok
  end

  test "browser edits private content and branding previews adds approved clip and resets", %{
    session: browser
  } do
    browser =
      browser
      |> demo_visit("/demo/admin")
      |> click(css("[data-test=admin-demo-start]"))
      |> assert_has(css("[data-test=admin-demo-bar]"))

    [org] = Repo.all(from o in Organization, where: o.demo_kind == :admin_sandbox)
    [video | _] = Repo.all(from v in Video, where: v.organization_id == ^org.id)

    browser =
      browser
      |> demo_visit("/admin/content")
      |> click(css("[data-test=view-video-#{video.id}]"))
      |> click(css("[data-test=edit-video-btn]"))
      |> fill_in(css("[data-test=video-title-input]"), with: "My private itinerary")
      |> click(css("[data-test=save-video-btn]"))
      |> assert_has(css("[data-test=video-title]", text: "My private itinerary"))
      |> demo_visit("/?preview=member")
      |> assert_has(css("[data-test=admin-demo-bar]"))
      |> assert_has(css("body", text: "My private itinerary"))
      |> demo_visit("/admin/appearance")
      |> assert_has(css("[data-phx-main].phx-connected"))
      |> replace_color("#123456")
      |> click(css("[data-test=save-branding-btn]"))
      |> assert_has(css("body", text: "Appearance saved."))

    assert_has(browser, css("[data-test=admin-demo-bar]"))

    browser =
      browser |> demo_visit("/?preview=member") |> assert_has(css("[data-test=admin-demo-bar]"))

    assert Branding.get_theme_by_org(org).background == "#123456"

    browser =
      browser
      |> demo_visit("/admin/demo/library")
      |> click(css("[data-test=sample-clip-travel-fixture-4]"))
      |> demo_visit("/admin/content")
      |> assert_has(css("body", text: "Travel fixture 4"))
      |> click(css("[data-test=admin-demo-reset]"))
      |> assert_has(css("[data-test=kpi-total-views]"))
      |> assert_has(css("[data-test=admin-demo-bar]"))
      |> demo_visit("/admin/content")
      |> assert_has(css("[data-test=video-list]"))

    refute_has(browser, css("body", text: "My private itinerary"))

    assert Repo.aggregate(from(o in Organization, where: o.demo_kind == :admin_sandbox), :count) ==
             2

    browser
    |> click(css("[data-test=admin-demo-exit]"))
    |> assert_has(css("[data-test=admin-demo-bar]", count: 0))

    assert current_url(browser) == MarqueeWeb.Endpoint.url() <> "/"
  end

  test "separate browser cookies isolate edits and persisted expiry blocks refresh", %{
    session: browser
  } do
    browser =
      browser
      |> demo_visit("/demo/admin")
      |> click(css("[data-test=admin-demo-start]"))
      |> assert_has(css("[data-test=admin-demo-bar]"))

    [org] = Repo.all(from o in Organization, where: o.demo_kind == :admin_sandbox)
    video = Repo.one!(from v in Video, where: v.organization_id == ^org.id, limit: 1)
    Repo.update!(Ecto.Changeset.change(video, title: "Only first browser"))
    metadata = Sandbox.metadata_for(Repo, self())
    {:ok, other} = Wallaby.start_session(metadata: metadata)
    on_exit(fn -> Wallaby.end_session(other) end)

    other =
      other
      |> demo_visit("/demo/admin")
      |> click(css("[data-test=admin-demo-start]"))
      |> assert_has(css("[data-test=admin-demo-bar]"))
      |> demo_visit("/admin/content")
      |> assert_has(css("[data-test=video-list]"))

    refute_has(other, css("body", text: "Only first browser"))
    session = Repo.get_by!(Session, organization_id: org.id)
    Repo.update!(Ecto.Changeset.change(session, expires_at: DateTime.add(DateTime.utc_now(), -1)))
    browser |> demo_visit("/admin") |> assert_has(css("[data-test=admin-demo-entry-form]"))
    other |> demo_visit("/admin") |> assert_has(css("[data-test=admin-demo-bar]"))
  end

  defp demo_visit(browser, path) do
    url = %{URI.parse(MarqueeWeb.Endpoint.url()) | host: "demo.localhost", path: nil, query: nil}
    visit(browser, URI.to_string(url) <> path)
  end

  defp replace_color(browser, value) do
    modifier = if match?({:unix, :darwin}, :os.type()), do: :command, else: :control

    browser
    |> click(css("[data-test=color-input-background] input[type=text]"))
    |> send_keys([modifier, "a", :null, value, :tab])
  end
end
