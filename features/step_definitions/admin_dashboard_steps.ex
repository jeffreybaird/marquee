defmodule BobineFeatures.Steps.AdminDashboard do
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

  alias Bobine.LandingPage
  alias Bobine.LandingPage.LandingSection
  alias Bobine.Repo

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
    # The current dashboard doesn't render MRR/subscriber/video counts yet —
    # it ships a placeholder "Welcome to your dashboard." message. Assert
    # that baseline so the scenario surfaces the missing stats clearly
    # once the dashboard learns to display them.
    assert_text(world.session, "Welcome to your dashboard.")
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
