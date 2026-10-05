defmodule MarqueeWeb.E2E.SubscriberDemoColdEntryTest do
  use MarqueeWeb.WallabyCase

  import Ecto.Query

  alias Marquee.{Engagement, Repo, SubscriberDemo}
  alias Marquee.Viewers.Viewer

  @moduletag :e2e

  setup do
    changes = [
      subscriber_demo_catalog: Marquee.SubscriberDemoFixtures.catalog_manifest(),
      org_resolution: :query_param,
      tenant_domain_provisioning: [enabled: false]
    ]

    original = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    org =
      insert(:organization,
        features: %{"subscriber_demo" => true},
        accent_color_base: "oklch(0.68 0.14 80)",
        accent_color_hover: "oklch(0.74 0.14 80)",
        accent_color_active: "oklch(0.62 0.14 80)",
        accent_color_subtle: "oklch(0.28 0.06 80)"
      )

    insert(:theme,
      organization: org,
      background: "#0f0b08",
      brand_primary: "#c4941a",
      brand_primary_hover: "#d4a42a",
      text_on_accent: "#ffffff"
    )

    {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    %{org: org, catalog: catalog}
  end

  test "cold browser previews the themed landing on desktop and mobile then explicitly begins a persistent demo",
       %{session: session, org: org, catalog: catalog} do
    session =
      session
      |> resize_window(1280, 900)
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=subscriber-demo-landing]"))
      |> assert_has(css("[data-test=hero-image-section] img"))

    assert_cta_contrast(session)
    session = hover(session, css("[data-test=subscriber-demo-entry]"))
    Process.sleep(300)
    assert_cta_contrast(session)

    assert Repo.aggregate(from(v in Viewer, where: v.organization_id == ^org.id), :count) == 0

    session =
      session
      |> resize_window(390, 844)
      |> assert_has(css("[data-test=subscriber-demo-entry]", text: "Begin demo"))
      |> click(css("[data-test=subscriber-demo-entry]"))
      |> assert_has(css("[data-test=subscriber-demo-banner]"))
      |> resize_window(1280, 900)
      |> assert_has(css("[data-test=hero-primary-cta-0]"))

    [viewer] = Repo.all(from(v in Viewer, where: v.organization_id == ^org.id))
    assert SubscriberDemo.demo_viewer?(viewer)
    video = hd(catalog.videos)
    assert {:ok, saved} = Engagement.add_to_watchlist(org, viewer, video)

    session =
      session
      |> click(css("[data-test=nav-my-stuff]"))
      |> assert_has(css("[data-test=sv-watchlist-remove-#{saved.video_id}]"))
      |> click(css("[data-test=sv-watchlist-remove-#{saved.video_id}]"))
      |> assert_has(css("[data-test=sv-watchlist-remove-#{saved.video_id}]", count: 0))
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=subscriber-demo-banner]"))

    assert_has(session, css("[data-test=hero-primary-cta-0]"))
    assert [persisted] = Repo.all(from(v in Viewer, where: v.organization_id == ^org.id))
    assert persisted.id == viewer.id
    refute Engagement.in_watchlist?(org, viewer, video)
  end

  defp assert_cta_contrast(session) do
    execute_script(
      session,
      """
      const e=document.querySelector('[data-test="subscriber-demo-entry"]');
      const canvas=document.createElement('canvas');canvas.width=canvas.height=1;
      const ctx=canvas.getContext('2d');
      const color=s=>{ctx.clearRect(0,0,1,1);ctx.fillStyle=s;ctx.fillRect(0,0,1,1);return Array.from(ctx.getImageData(0,0,1,1).data).map(x=>x/255)};
      const blend=(fg,bg)=>fg.slice(0,3).map((x,i)=>x*fg[3]+bg[i]*(1-fg[3]));
      const c=getComputedStyle(e), backdrop=[15/255,11/255,8/255];
      const bg=blend(color(c.backgroundColor),backdrop), fg=blend(color(c.color),bg);
      const opacity=Number(c.opacity), composite=x=>x.map((v,i)=>v*opacity+backdrop[i]*(1-opacity));
      const luminance=x=>x.map(v=>v<=0.04045?v/12.92:Math.pow((v+0.055)/1.055,2.4)).reduce((a,v,i)=>a+v*[0.2126,0.7152,0.0722][i],0);
      const l1=luminance(composite(fg)),l2=luminance(composite(bg));
      return {ratio:(Math.max(l1,l2)+0.05)/(Math.min(l1,l2)+0.05), background:color(c.backgroundColor), expected:color("oklch(0.68 0.14 80)")};
      """,
      fn result ->
        assert result["background"] == result["expected"]
        assert result["ratio"] >= 4.5
      end
    )
  end
end
