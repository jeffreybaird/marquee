defmodule MarqueeWeb.E2E.PlatformHomeSessionTest do
  use MarqueeWeb.WallabyCase

  import Ecto.Query
  alias Marquee.Repo
  alias Marquee.Viewers.Viewer

  @moduletag :e2e

  setup do
    original = Application.fetch_env(:marquee, :org_resolution)
    Application.put_env(:marquee, :org_resolution, :query_param)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:marquee, :org_resolution, value)
        :error -> Application.delete_env(:marquee, :org_resolution)
      end
    end)

    org = insert(:organization, features: %{"subscriber_demo" => true})
    insert(:video, organization: org, published: true, mux_status: "ready")
    %{org: org}
  end

  test "tenant visit followed by bare platform home shows marketing without discarding the demo cookie",
       %{session: session, org: org} do
    session =
      session
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=subscriber-demo-entry]", text: "Begin demo"))
      |> click(css("[data-test=subscriber-demo-entry]"))
      |> assert_has(css("[data-test=subscriber-demo-banner]"))

    assert [viewer] = Repo.all(from(v in Viewer, where: v.organization_id == ^org.id))

    session =
      session
      |> visit("/")
      |> assert_has(css("[data-test=platform-marketing]"))
      |> assert_has(css("[data-test=marketing-headline]"))

    assert_has(session, css("[data-test=subscriber-demo-banner]", count: 0))
    session |> visit("/?org=#{org.slug}") |> assert_has(css("[data-test=subscriber-demo-banner]"))
    assert [reused] = Repo.all(from(v in Viewer, where: v.organization_id == ^org.id))
    assert reused.id == viewer.id
  end
end
