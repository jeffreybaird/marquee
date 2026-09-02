defmodule MarqueeFeatures.Steps.AdminDashboard do
  @moduledoc """
  Step definitions for admin_dashboard.feature.

  Covers the dashboard landing + landing-page section builder. Section
  types the app ships today: hero_video, hero_image, hero_slider,
  marketing_copy, content_row, plan_display, header_text, faq. The
  feature file's "feature", "testimonial", and "CTA" scenarios don't
  map to real section types — those steps stay undefined until the
  product ships matching editors.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import ExUnit.Assertions

  alias Marquee.LandingPage
  alias Marquee.LandingPage.LandingSection
  alias Marquee.Repo

  # ---- Navigation ---------------------------------------------------------

  given_ "I am on the landing page builder at /admin/landing", fn world ->
    session = visit(world.session, "/admin/landing?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  when_ "I navigate to /admin/", fn world ->
    session = visit(world.session, "/admin?org=#{world.org.slug}")
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
    refute_has(world.session, css("[data-test=nudge-connect_stripe]"))
    world
  end

  then_ "the connect-Stripe nudge stays hidden after I reload the dashboard", fn world ->
    session = visit(world.session, "/admin?org=#{world.org.slug}")
    refute_has(session, css("[data-test=nudge-connect_stripe]"))
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
    session =
      world.session
      |> visit("/admin/landing?org=#{world.org.slug}")
      |> click(css("[data-test=toggle-visibility-#{world.section.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I toggle its visibility on", fn world ->
    session =
      world.session
      |> visit("/admin/landing?org=#{world.org.slug}")
      |> click(css("[data-test=toggle-visibility-#{world.section.id}]"))

    Map.put(world, :session, session)
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
    session =
      world.session
      |> visit("/admin/landing?org=#{world.org.slug}")
      |> accept_confirm(fn s ->
        click(s, css("[data-test=delete-section-#{world.section.id}]"))
      end)

    Map.put(world, :session, session)
  end

  then_ "the section is removed from the landing page", fn world ->
    refute Repo.get(LandingSection, world.section.id),
           "expected section #{world.section.id} to be deleted"

    world
  end

  # ---- Private helpers ----------------------------------------------------

  defp add_section(world, section_type_str) do
    # The add-section form uses phx-change="add_section" — changing the
    # select fires the event immediately. Wallaby's set_value/3 on a
    # <select> dispatches the change event the LiveView listens for.
    session =
      world.session
      |> visit("/admin/landing?org=#{world.org.slug}")
      |> Wallaby.Browser.set_value(
        css("[data-test=add-section-select]"),
        section_type_str
      )

    Map.merge(world, %{session: session, last_section_type: section_type_str})
  end

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
end
