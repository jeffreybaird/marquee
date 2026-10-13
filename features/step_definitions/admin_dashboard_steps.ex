defmodule MarqueeFeatures.Steps.AdminDashboard do
  @moduledoc """
  Step definitions for the admin dashboard features: the operator
  dashboard, the landing-page section builder, organization settings, and
  the super admin dashboard.

  Landing-page section types the app ships today: hero_video, hero_image,
  hero_slider, marketing_copy, content_row, plan_display, header_text, faq.
  The "feature", "testimonial", and "CTA" scenarios select those types in
  the add-section menu; they fail until the product ships matching types.

  "I toggle its visibility on/off" is shared wording across features, so
  its single definition here dispatches on the subject the scenario's
  Given put in the world (landing section, catalog row, collection,
  season, or series).
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Browser, except: [refute_has: 2]
  import Wallaby.Query
  import ExUnit.Assertions
  import Marquee.Factory
  import MarqueeFeatures.Support.Browser

  alias Marquee.Admin
  alias Marquee.Billing
  alias Marquee.Content
  alias Marquee.Content.MockMuxClient
  alias Marquee.Content.Video
  alias Marquee.LandingPage
  alias Marquee.LandingPage.LandingSection
  alias Marquee.Repo
  alias MarqueeFeatures.UploadStubServer

  # ---- Navigation ---------------------------------------------------------

  given_ "I am on the landing page builder at /admin/landing", fn world ->
    session = visit_live(world.session, "/admin/landing?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  when_ "I navigate to /admin/", fn world ->
    session = visit_live(world.session, "/admin?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  # ---- Dashboard view -----------------------------------------------------

  then_ "I see quick stats including subscriber count, video count, and MRR", fn world ->
    assert_text(world.session, "Dashboard")
    # The dashboard renders KPI tiles: active subscribers, MRR, total views,
    # and published-video count.
    assert_text(world.session, "Active Subscribers")
    assert_text(world.session, "MRR")
    assert_text(world.session, "Published Videos")
    world
  end

  then_ "I see links to all admin sections", fn world ->
    # Sidebar has Dashboard / Content / Collections / Series / Tags / Catalog
    # / Landing Page / Analytics / Appearance / Members / Webhooks /
    # Settings / Billing / Audit Log.
    for label <- ~w(Dashboard Content Collections Series Tags Catalog
                    Analytics Appearance Members Webhooks Settings Billing) do
      assert_text(world.session, label)
    end

    world
  end

  # ---- View member-facing site -------------------------------------------

  then_ "I see a link to view the member-facing site", fn world ->
    assert_has(world.session, css("[data-test=admin-view-site]"))
    world
  end

  given_ "my organization has a published video in a visible row", fn world ->
    video = insert(:video, organization: world.org, mux_status: "ready")

    row =
      insert(:row,
        organization: world.org,
        title: "Preview Row",
        source_type: :curated,
        visible: true,
        position: 0
      )

    insert(:row_item, organization: world.org, row: row, video: video, position: 0)
    world
  end

  when_ "I open the member-facing site preview", fn world ->
    session = visit(world.session, "/?org=#{world.org.slug}&preview=member")
    Map.put(world, :session, session)
  end

  then_ "I see the member-facing home instead of the admin dashboard", fn world ->
    # Landed on the viewer home (member site), not bounced back to /admin.
    assert_has(world.session, css("[data-test=sv-root]"))
    assert_text(world.session, "Preview Row")
    refute_has(world.session, css("[data-test=admin-nav-content]"))
    world
  end

  when_ "I navigate through the member preview pages", fn world ->
    session =
      Enum.reduce(["/browse", "/watchlist", "/history", "/account", "/"], world.session, fn path, session ->
        session = visit(session, path)
        assert_has(session, css("[data-test=impersonation-banner]"))
        session
      end)

    Map.put(world, :session, session)
  end

  then_ "the member preview remains signed in", fn world ->
    assert_text(world.session, "Member preview")
    assert_has(world.session, css("[data-test=sv-root]"))
    world
  end

  # ---- Setup nudges -------------------------------------------------------

  then_ "I see a setup nudge prompting me to connect Stripe", fn world ->
    assert_text(world.session, "Connect Stripe to accept payments")
    world
  end

  when_ "I dismiss the connect-Stripe setup nudge", fn world ->
    session = click(world.session, css("[data-test=dismiss-nudge-connect_stripe]"))
    Map.put(world, :session, session)
  end

  then_ "the connect-Stripe nudge no longer appears", fn world ->
    assert_has(world.session, css("[data-test=nudge-connect_stripe]", count: 0))
    world
  end

  then_ "the connect-Stripe nudge stays hidden after I reload the dashboard", fn world ->
    session = visit(world.session, "/admin?org=#{world.org.slug}")
    assert_has(session, css("[data-test=nudge-connect_stripe]", count: 0))
    Map.put(world, :session, session)
  end

  # ---- Landing page section CRUD -----------------------------------------

  when_ "I add a section of type hero", fn world ->
    add_section(world, "hero_video")
  end

  when_ "I add a section of type FAQ", fn world ->
    add_section(world, "faq")
  end

  when_ "I add a section of type video", fn world ->
    # Maps to the content_row section type — that's how the app surfaces
    # "a section that shows videos" today.
    add_section(world, "content_row")
  end

  then_ "a hero section appears in the landing page", fn world ->
    assert has_section_of_type?(world.org, :hero_video),
           "expected a hero_video section to exist on the landing page"

    session = visit(world.session, "/admin/landing?org=#{world.org.slug}")
    assert_text(session, "Hero video")
    Map.put(world, :session, session)
  end

  then_ "a FAQ section appears in the landing page", fn world ->
    assert has_section_of_type?(world.org, :faq),
           "expected a faq section to exist on the landing page"

    session = visit(world.session, "/admin/landing?org=#{world.org.slug}")
    assert_text(session, "FAQ")
    Map.put(world, :session, session)
  end

  then_ "a video section appears and I can link a video to it", fn world ->
    assert has_section_of_type?(world.org, :content_row)
    world
  end

  # ---- Edit / toggle visibility / delete ---------------------------------

  given_ "a landing page section exists", fn world ->
    section = insert_section!(world.scope, :marketing_copy)
    Map.put(world, :section, section)
  end

  given_ "a landing page section is hidden", fn world ->
    section = insert_section!(world.scope, :marketing_copy, visible: false)
    Map.put(world, :section, section)
  end

  when_ "I toggle its visibility off", fn world ->
    toggle_subject_visibility(world, false)
  end

  when_ "I toggle its visibility on", fn world ->
    toggle_subject_visibility(world, true)
  end

  then_ "that section is hidden from public visitors", fn world ->
    section = Repo.get!(LandingSection, world.section.id)
    refute section.visible
    world
  end

  then_ "that section appears for public visitors", fn world ->
    section = Repo.get!(LandingSection, world.section.id)
    assert section.visible
    world
  end

  when_ "I delete the section", fn world ->
    session = visit_live(world.session, "/admin/landing?org=#{world.org.slug}")

    accept_confirm(session, fn s ->
      click(s, css("[data-test=delete-section-#{world.section.id}]"))
    end)

    Map.put(world, :session, session)
  end

  then_ "the section is removed from the landing page", fn world ->
    # Landing sections are user-facing content, so removal is a soft delete:
    # the row keeps a `deleted_at` timestamp and leaves the editor list.
    assert_has(world.session, css("[data-test=section-item-#{world.section.id}]", count: 0))

    section = Repo.get!(LandingSection, world.section.id)
    assert section.deleted_at, "expected section #{world.section.id} to be soft-deleted"

    %{results: sections} = LandingPage.list_landing_sections_admin(world.org)

    refute Enum.any?(sections, &(&1.id == world.section.id)),
           "expected section #{world.section.id} to be absent from the admin section list"

    world
  end

  # ---- Dashboard stats -----------------------------------------------------

  given_ "my organization has subscribers, videos, and revenue", fn world ->
    org = world.org
    baseline_published = Content.count_published_videos(org)

    # Three subscribers on a $10.00 monthly plan. Each keeps the default 2%
    # platform fee, so the organization nets 980 cents a month per
    # subscriber.
    plan = insert(:plan, organization: org, amount: 1000, interval: :monthly)

    # Published-video counts are read live (not cached), so seeding videos
    # before the dashboard is first rendered does not affect the cache.
    for n <- 1..2 do
      insert(:video,
        organization: org,
        title: "Dashboard Published #{n}",
        mux_status: "ready",
        published: true
      )
    end

    insert(:video, organization: org, title: "Dashboard Draft", mux_status: "ready", published: false)

    # Render the dashboard before any subscriber exists and wait for its
    # stats. This deterministically fills the overview cache, so the
    # scenario proves that subscription changes refresh the stats rather
    # than depending on whether login happened to warm the cache first.
    session = visit_live(world.session, "/admin?org=#{org.slug}")
    session = await_kpi(session, "kpi-active-subscribers", "0")
    session = await_kpi(session, "kpi-mrr", "$0.00")

    # Subscribers arrive through the same Billing functions the Stripe
    # checkout webhook uses, so every domain event a real signup emits is
    # broadcast.
    for n <- 1..3 do
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      checkout_session = %{
        "subscription" => "sub_dashboard_#{org.id}_#{n}",
        "customer" => "cus_dashboard_#{org.id}_#{n}",
        "line_items" => %{"data" => [%{"price" => %{"id" => plan.stripe_price_id}}]}
      }

      {:ok, subscription} = Billing.create_subscription_from_checkout(org, viewer, checkout_session)
      :ok = Billing.activate_viewer_subscription(org, viewer, subscription)
    end

    world
    |> Map.put(:session, session)
    |> Map.put(:expected_stats, %{
      "kpi-active-subscribers" => "3",
      "kpi-mrr" => "$29.40",
      "kpi-published-videos" => Integer.to_string(baseline_published + 2)
    })
  end

  when_ "I view the dashboard", fn world ->
    session = visit_live(world.session, "/admin?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  then_ "the displayed stats match the current organization data", fn world ->
    session =
      Enum.reduce(world.expected_stats, world.session, fn {card, expected}, session ->
        await_kpi(session, card, expected)
      end)

    Map.put(world, :session, session)
  end

  # ---- Super admin dashboard -------------------------------------------------

  when_ "I navigate to /super/", fn world ->
    session =
      world.session
      |> resize_window(1440, 1000)
      |> visit_live("/super")

    Map.put(world, :session, session)
  end

  then_ "I see platform-level stats", fn world ->
    stats = Admin.platform_stats()

    expected = %{
      "stat-total-orgs" => stats.total_organizations,
      "stat-total-users" => stats.total_users,
      "stat-total-videos" => stats.total_videos,
      "stat-total-subscribers" => stats.total_subscribers
    }

    for {card, value} <- expected do
      assert_has(world.session, css("[data-test=#{card}]"))
      actual = kpi_value(world.session, card)

      assert actual == Integer.to_string(value),
             "expected #{card} to show #{value}, got #{inspect(actual)}"
    end

    world
  end

  then_ "I see links to organizations, users, analytics, and the audit log", fn world ->
    links = %{
      "super-nav-organizations" => "/super/organizations",
      "super-nav-users" => "/super/users",
      "super-nav-analytics" => "/super/analytics",
      "super-nav-audit-log" => "/super/audit-log"
    }

    for {link, path} <- links do
      href =
        world.session
        |> find(css("a[data-test=#{link}]"))
        |> Element.attr("href")

      assert URI.parse(href).path == path, "expected #{link} to link to #{path}, got #{href}"
    end

    world
  end

  # ---- Organization settings -------------------------------------------------

  given_ "I am on the organization settings page", fn world ->
    session = visit_live(world.session, "/admin/settings?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  when_ "I view the settings page", fn world ->
    session =
      world.session
      |> visit_live("/admin/settings?org=#{world.org.slug}")
      |> assert_has(css("[data-test=stripe-connect-section]"))

    Map.put(world, :session, session)
  end

  then_ "I see whether Stripe Connect is connected or pending", fn world ->
    org = Repo.reload!(world.org)

    if org.stripe_connect_onboarding_complete do
      world.session
      |> assert_has(css("[data-test=stripe-connected-status]", text: "Stripe connected"))
      |> refute_has(css("[data-test=stripe-not-connected]"))
    else
      world.session
      |> assert_has(css("[data-test=stripe-not-connected] [data-test=connect-stripe-btn]"))
      |> refute_has(css("[data-test=stripe-connected-status]"))
    end

    world
  end

  given_ "Stripe Connect is not yet connected", fn world ->
    org = Repo.reload!(world.org)
    refute org.stripe_connect_onboarding_complete
    assert_has(world.session, css("[data-test=stripe-not-connected]"))
    Map.put(world, :org, org)
  end

  # ---- Landing page: section types without an editor ------------------------

  when_ "I add a section of type feature", fn world ->
    add_section(world, "feature")
  end

  when_ "I add a section of type testimonial", fn world ->
    add_section(world, "testimonial")
  end

  when_ "I add a section of type CTA", fn world ->
    add_section(world, "cta")
  end

  then_ "a feature section appears in the landing page", fn world ->
    assert_section_type_listed(world, "feature")
  end

  then_ "a testimonial section appears in the landing page", fn world ->
    assert_section_type_listed(world, "testimonial")
  end

  then_ "a CTA section appears in the landing page", fn world ->
    assert_section_type_listed(world, "cta")
  end

  # ---- Landing page: editing content -----------------------------------------

  when_ "I edit its content and save", fn world ->
    headline = "Fresh Headline #{System.unique_integer([:positive])}"

    session =
      world.session
      |> open_section_editor(world.section)
      |> fill_in(css("[data-test=section-editor] input[name=headline]"), with: headline)
      |> save_section_editor()

    Map.merge(world, %{session: session, new_headline: headline})
  end

  then_ "the updated content is published to the landing page", fn world ->
    section = Repo.get!(LandingSection, world.section.id)
    assert section.config["headline"] == world.new_headline

    html = public_landing_html(world.org)
    assert html =~ ~s(data-test="landing-section-#{section.id}")
    assert html =~ world.new_headline
    world
  end

  # ---- Landing page: FAQ items -------------------------------------------------

  given_ "a FAQ section exists", fn world ->
    section = insert_section!(world.scope, :faq)
    Map.put(world, :section, section)
  end

  given_ "a FAQ section has items", fn world ->
    # Distinct wording: the starter sections the builder seeds include their
    # own FAQ questions.
    items = [
      %{"question" => "Which regions stream the backstage cut?", "answer" => "All of them."},
      %{"question" => "Are director commentaries subtitled?", "answer" => "In four languages."}
    ]

    {:ok, section} =
      LandingPage.create_landing_section(world.scope, %{
        section_type: :faq,
        visible: true,
        config: %{"headline" => "Questions", "items" => items}
      })

    Map.merge(world, %{section: section, faq_items: items})
  end

  when_ "I add a question and answer pair", fn world ->
    question = "How many devices can I use? #{System.unique_integer([:positive])}"
    answer = "Up to four at once."

    session =
      world.session
      |> open_section_editor(world.section)
      |> click(css("[data-test=section-editor] button[phx-click=faq_add_item]"))
      |> assert_has(css("[data-test=faq-edit-item-0]"))
      |> fill_in(css("[data-test=faq-edit-item-0] input"), with: question)
      |> fill_in(css("[data-test=faq-edit-item-0] textarea"), with: answer)
      |> save_section_editor()

    Map.put(world, :faq_item, %{"question" => question, "answer" => answer})
    |> Map.put(:session, session)
  end

  then_ "the FAQ item appears within the FAQ section", fn world ->
    section = Repo.get!(LandingSection, world.section.id)
    assert section.config["items"] == [world.faq_item]

    html = public_landing_html(world.org)
    assert html =~ ~s(data-test="faq-item-0")
    assert html =~ world.faq_item["question"]
    world
  end

  when_ "I remove a FAQ item", fn world ->
    session =
      world.session
      |> open_section_editor(world.section)
      |> assert_has(css("[data-test=faq-edit-item-1]"))
      |> click(css("[data-test=faq-edit-item-0] button[phx-click=faq_remove_item]"))
      |> assert_has(css("[data-test=faq-edit-item-1]", count: 0))
      |> save_section_editor()

    [removed, kept] = world.faq_items
    Map.merge(world, %{session: session, removed_faq_item: removed, kept_faq_item: kept})
  end

  then_ "it is removed from the FAQ section", fn world ->
    section = Repo.get!(LandingSection, world.section.id)
    assert section.config["items"] == [world.kept_faq_item]

    html = public_landing_html(world.org)
    assert html =~ world.kept_faq_item["question"]
    refute html =~ world.removed_faq_item["question"]
    world
  end

  # ---- Landing page: reorder -------------------------------------------------------

  given_ "the landing page has multiple sections", fn world ->
    for label <- ["First", "Second", "Third"] do
      {:ok, _} =
        LandingPage.create_landing_section(world.scope, %{
          section_type: :marketing_copy,
          visible: true,
          config: %{"headline" => "#{label} Section", "body" => "#{label} body"}
        })
    end

    # The builder seeds starter sections for an empty landing page, so the
    # list holds those plus the three created here.
    %{results: sections} = LandingPage.list_landing_sections_admin(world.org)
    assert length(sections) >= 3
    Map.put(world, :sections, sections)
  end

  when_ "I move a section up or down", fn world ->
    [first, second | rest] = world.sections

    session =
      world.session
      |> visit_live("/admin/landing?org=#{world.org.slug}")
      |> click(css("[data-test=section-item-#{first.id}] button[phx-click=move_down]"))
      |> assert_has(
        css("[data-test=section-list] > div:first-child[data-test=section-item-#{second.id}]")
      )

    Map.merge(world, %{session: session, expected_section_order: [second.id, first.id | Enum.map(rest, & &1.id)]})
  end

  then_ "the display order updates accordingly", fn world ->
    %{results: sections} = LandingPage.list_landing_sections_admin(world.org)
    assert Enum.map(sections, & &1.id) == world.expected_section_order

    html = public_landing_html(world.org)

    positions =
      Enum.map(world.expected_section_order, fn id ->
        {index, _} = :binary.match(html, ~s(data-test="landing-section-#{id}"))
        index
      end)

    assert positions == Enum.sort(positions),
           "expected the public landing page to render sections in the new order"

    world
  end

  # ---- Landing page: video picker ----------------------------------------------

  given_ "a video section exists and videos are available", fn world ->
    section = insert_section!(world.scope, :hero_video)

    video =
      insert(:video,
        organization: world.org,
        title: "Landing Picker Video #{System.unique_integer([:positive])}",
        mux_status: "ready",
        published: true
      )

    assert is_binary(video.mux_playback_id) and video.mux_playback_id != ""
    Map.merge(world, %{section: section, picker_video: video})
  end

  given_ "a video section exists", fn world ->
    section = insert_section!(world.scope, :hero_video)
    Map.put(world, :section, section)
  end

  when_ "I open the video picker and select an existing video", fn world ->
    video = world.picker_video

    session =
      world.session
      |> open_section_editor(world.section)
      |> click(css("[data-test=landing-open-video-picker]"))
      |> assert_has(css("[data-test=landing-video-select-#{video.id}]"))
      |> click(css("div:has(> div > [data-test=landing-video-select-#{video.id}]) > button"))
      |> assert_has(css("[data-test=landing-video-select-#{video.id}]", count: 0))
      |> save_section_editor()

    Map.put(world, :session, session)
  end

  then_ "the video is linked to that landing page section", fn world ->
    section = Repo.get!(LandingSection, world.section.id)
    assert section.config["video_playback_id"] == world.picker_video.mux_playback_id

    html = public_landing_html(world.org)
    assert html =~ ~s(data-test="landing-section-#{section.id}")
    assert html =~ world.picker_video.mux_playback_id
    world
  end

  when_ "I upload a new video file via the video picker", fn world ->
    upload_id = "landing_upload_#{System.unique_integer([:positive])}"
    stub = UploadStubServer.start(self())
    upload_url = "#{stub.base_url}/mux/#{upload_id}"
    file_path = write_upload_fixture()

    Mox.set_mox_global()

    Mox.stub(MockMuxClient, :create_direct_upload, fn _params ->
      {:ok, %{"id" => upload_id, "url" => upload_url}}
    end)

    try do
      session =
        world.session
        |> open_section_editor(world.section)
        |> click(css("[data-test=landing-open-video-picker]"))
        |> click(css("[data-test=landing-picker-tab-upload]"))
        |> attach_file(css("[data-test=upload-file]"), path: file_path)
        |> assert_has(css("[data-test=landing-upload-title]"))
        |> click(css("[data-test=landing-upload-submit]"))

      assert_receive {:upload_stub_received, _handler, request_path, body}, 15_000
      assert request_path == "/mux/#{upload_id}"

      session =
        session
        |> assert_has(css("[data-test=section-editor]", text: "Upload pending"))
        |> save_section_editor()

      Map.merge(world, %{
        session: session,
        upload_id: upload_id,
        uploaded_body: body,
        upload_fixture: File.read!(file_path)
      })
    after
      Mox.set_mox_private()
      UploadStubServer.stop(stub)
    end
  end

  then_ "the video is uploaded to Mux", fn world ->
    assert world.uploaded_body == world.upload_fixture,
           "expected the selected file's bytes to be sent to the Mux direct-upload URL"

    video = Repo.get_by!(Video, organization_id: world.org.id, mux_upload_id: world.upload_id)
    assert video.mux_status == "waiting"
    Map.put(world, :uploaded_video, video)
  end

  then_ "linked to that landing page section", fn world ->
    section = Repo.get!(LandingSection, world.section.id)
    assert section.config["pending_video_id"] == world.uploaded_video.id
    world
  end

  # ---- Private helpers ----------------------------------------------------

  defp add_section(world, section_type_str) do
    # The add-section select fires phx-change="add_section"; clicking the
    # <option> is what dispatches the change event (see select_option/3).
    session =
      world.session
      |> visit_live("/admin/landing?org=#{world.org.slug}")
      |> select_option("[data-test=add-section-select]", section_type_str)
      |> assert_has(css("[data-test=section-editor]"))

    Map.merge(world, %{session: session, last_section_type: section_type_str})
  end

  defp assert_section_type_listed(world, section_type_str) do
    %{results: sections} = LandingPage.list_landing_sections_admin(world.org)

    section = Enum.find(sections, &(to_string(&1.section_type) == section_type_str))
    assert section, "expected a #{section_type_str} section on the landing page"

    session =
      world.session
      |> visit_live("/admin/landing?org=#{world.org.slug}")
      |> assert_has(css("[data-test=section-item-#{section.id}]"))

    Map.put(world, :session, session)
  end

  defp open_section_editor(session, section) do
    session
    |> visit_live("/admin/landing?org=#{section_org_slug(section)}")
    |> click(css("[data-test=edit-section-#{section.id}]"))
    |> assert_has(css("[data-test=section-editor]"))
  end

  defp section_org_slug(section) do
    section
    |> Repo.preload(:organization)
    |> Map.fetch!(:organization)
    |> Map.fetch!(:slug)
  end

  defp save_section_editor(session) do
    # The builder does not render flash messages (see the report), so the
    # editor closing is the visible signal that the save succeeded.
    session
    |> click(css("[data-test=save-section]"))
    |> assert_has(css("[data-test=section-editor]", count: 0))
  end

  defp public_landing_html(org) do
    base_url = Application.fetch_env!(:wallaby, :base_url)
    %Req.Response{status: 200, body: body} = Req.get!("#{base_url}/?org=#{org.slug}", retry: false)
    body
  end

  # Polls a KPI card until it shows exactly `expected`, then fails with the
  # last value seen. Stats render on mount and may re-render on events, so
  # a single read could race a pending update.
  defp await_kpi(session, card, expected, timeout_ms \\ 10_000) do
    assert_has(session, css("[data-test=#{card}] p:last-child"))
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_kpi_until(session, card, expected, deadline)
  end

  defp await_kpi_until(session, card, expected, deadline) do
    actual = kpi_value(session, card)

    cond do
      actual == expected ->
        session

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("expected #{card} to show #{expected}, got #{inspect(actual)}")

      true ->
        Process.sleep(250)
        await_kpi_until(session, card, expected, deadline)
    end
  end

  defp kpi_value(session, card) do
    session
    |> find(css("[data-test=#{card}] p:last-child"))
    |> Element.text()
    |> String.trim()
  end

  defp write_upload_fixture do
    dir = Path.join(System.tmp_dir!(), "marquee-features")
    File.mkdir_p!(dir)
    path = Path.join(dir, "landing-upload-#{System.unique_integer([:positive])}.mp4")
    File.write!(path, :crypto.strong_rand_bytes(4096))
    path
  end

  # "I toggle its visibility on/off": the subject is whatever the scenario's
  # Given put in the world. Each branch clicks the admin UI toggle and waits
  # for its label to flip before returning.
  defp toggle_subject_visibility(%{section: section} = world, visible?) do
    selector = "[data-test=toggle-visibility-#{section.id}]"

    session =
      world.session
      |> visit_live("/admin/landing?org=#{world.org.slug}")
      |> click(css(selector))
      |> assert_has(css(selector, text: if(visible?, do: "Hide", else: "Show")))

    Map.put(world, :session, session)
  end

  defp toggle_subject_visibility(%{row: row} = world, visible?) do
    selector = "[data-test=row-#{row.id}] [data-test=row-visibility-toggle]"

    session =
      world.session
      |> visit_live("/admin/catalog?org=#{world.org.slug}")
      |> click(css(selector))
      |> assert_has(css(selector, text: visibility_label(visible?)))

    Map.put(world, :session, session)
  end

  defp toggle_subject_visibility(%{collection: collection} = world, visible?) do
    selector = "button[data-test=collection-visibility-toggle][phx-value-id='#{collection.id}']"

    session =
      world.session
      |> visit_live("/admin/collections?org=#{world.org.slug}")
      |> click(css(selector))
      |> assert_has(css(selector, text: visibility_label(visible?)))

    Map.put(world, :session, session)
  end

  # "a season exists" also stores the sibling season it leaves visible; the
  # series scenarios do not, so that key marks a season-level toggle.
  defp toggle_subject_visibility(%{season: season, other_season: _} = world, visible?) do
    selector = "[data-test=season-visibility-#{season.id}]"

    session =
      world.session
      |> visit_live("/admin/series?org=#{world.org.slug}")
      |> click(css("[data-test=view-series-#{world.series.id}]"))
      |> click(css(selector))
      |> assert_has(css(selector, text: visibility_label(visible?)))

    Map.put(world, :session, session)
  end

  defp toggle_subject_visibility(%{series: series} = world, visible?) do
    selector = "[data-test=series-visibility-#{series.id}]"

    session =
      world.session
      |> visit_live("/admin/series?org=#{world.org.slug}")
      |> click(css(selector))
      |> assert_has(css(selector, text: visibility_label(visible?)))

    Map.put(world, :session, session)
  end

  defp visibility_label(true), do: "Visible"
  defp visibility_label(false), do: "Hidden"

  defp insert_section!(scope, type, opts \\ []) do
    visible = Keyword.get(opts, :visible, true)

    {:ok, section} =
      LandingPage.create_landing_section(scope, %{
        section_type: type,
        visible: visible,
        config: default_config_for(type)
      })

    section
  end

  defp default_config_for(:faq), do: %{"items" => []}
  defp default_config_for(:marketing_copy), do: %{"headline" => "Heading", "body" => "Body"}
  defp default_config_for(_), do: %{}

  defp has_section_of_type?(org, type) do
    import Ecto.Query

    Repo.exists?(
      from s in LandingSection,
        where: s.organization_id == ^org.id and s.section_type == ^type
    )
  end

  # Wallaby's refute_has/2 checks once and fails while an element is still
  # leaving the DOM after a LiveView patch. Asserting a count of zero retries
  # until the element is gone (or the query times out).
  defp refute_has(parent, query), do: assert_has(parent, Wallaby.Query.count(query, 0))
end
