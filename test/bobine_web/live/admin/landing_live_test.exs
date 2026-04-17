defmodule BobineWeb.Admin.LandingLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bobine.Accounts.Scope
  alias Bobine.LandingPage

  defp build_scope(membership) do
    membership = Bobine.Repo.preload(membership, [:user, :organization])

    Scope.for_user(membership.user)
    |> Scope.with_organization(membership.organization, membership)
  end

  describe "access control" do
    test "admin can access the landing editor" do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/landing")
      assert html =~ "Landing Page"
    end

    test "viewer_support can access the landing editor" do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/landing")
      assert html =~ "Landing Page"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/landing")
      assert path == ~p"/users/log-in"
    end
  end

  describe "first visit seeding" do
    test "seeds default sections when org has none" do
      membership = insert(:membership, role: :admin)
      {:ok, _view, _html} = live(conn_for(membership), ~p"/admin/landing")

      %{total: total} = LandingPage.list_landing_sections_admin(membership.organization)
      assert total == 5
    end

    test "does not re-seed if sections already exist" do
      membership = insert(:membership, role: :admin)
      scope = build_scope(membership)

      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Existing"}
        })

      {:ok, _view, _html} = live(conn_for(membership), ~p"/admin/landing")
      %{total: total} = LandingPage.list_landing_sections_admin(membership.organization)
      assert total == 1
    end
  end

  describe "section list" do
    test "renders all sections (visible and hidden)" do
      membership = insert(:membership, role: :admin)
      scope = build_scope(membership)

      {:ok, visible} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          visible: true,
          config: %{"headline" => "Visible One"}
        })

      {:ok, hidden} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          visible: false,
          config: %{"headline" => "Hidden One"}
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

      assert has_element?(view, "[data-test=section-item-#{visible.id}]")
      assert has_element?(view, "[data-test=section-item-#{hidden.id}]")
      assert render(view) =~ "Visible One"
      assert render(view) =~ "Hidden One"
    end
  end

  describe "add section" do
    test "creates a new section of the chosen type and opens the editor" do
      membership = insert(:membership, role: :admin)
      scope = build_scope(membership)

      # Pre-seed one section so seeding doesn't run
      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Seed"}
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

      view
      |> element("#add-section-form")
      |> render_change(%{"section_type" => "marketing_copy"})

      %{results: sections} = LandingPage.list_landing_sections_admin(membership.organization)
      assert Enum.any?(sections, &(&1.section_type == :marketing_copy))
      assert has_element?(view, "[data-test=section-editor]")
    end

    for type_str <-
          ~w(hero_video hero_image hero_slider marketing_copy content_row plan_display header_text faq) do
      test "can add a #{type_str} section without a validation error" do
        membership = insert(:membership, role: :admin)
        scope = build_scope(membership)

        # Pre-seed so the auto-seed doesn't run.
        {:ok, _} =
          LandingPage.create_landing_section(scope, %{
            section_type: :header_text,
            config: %{"headline" => "Seed"}
          })

        {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

        view
        |> element("#add-section-form")
        |> render_change(%{"section_type" => unquote(type_str)})

        type = String.to_existing_atom(unquote(type_str))

        %{results: sections} = LandingPage.list_landing_sections_admin(membership.organization)

        assert Enum.any?(sections, &(&1.section_type == type)),
               "expected a #{unquote(type_str)} section to be created"

        rendered = render(view)
        refute rendered =~ "Could not add section"
      end
    end
  end

  describe "edit + save section" do
    test "updates section config" do
      membership = insert(:membership, role: :admin)
      scope = build_scope(membership)

      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{
            "headline" => "Old",
            "size" => "large",
            "text_alignment" => "center"
          }
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

      view
      |> element("[data-test=edit-section-#{section.id}]")
      |> render_click()

      assert has_element?(view, "[data-test=section-editor]")

      view
      |> element("[data-test=section-editor] form")
      |> render_submit(%{
        "headline" => "New",
        "subheadline" => "Sub",
        "size" => "small",
        "text_alignment" => "left",
        "visible" => "true"
      })

      {:ok, updated} = LandingPage.get_landing_section(membership.organization, section.id)
      assert updated.config["headline"] == "New"
      assert updated.config["size"] == "small"
    end
  end

  describe "delete section" do
    test "soft-deletes the section and removes it from the list" do
      membership = insert(:membership, role: :admin)
      scope = build_scope(membership)

      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Doomed"}
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

      view
      |> element("[data-test=delete-section-#{section.id}]")
      |> render_click()

      refute has_element?(view, "[data-test=section-item-#{section.id}]")
    end
  end

  describe "toggle visibility" do
    test "flips the visible flag" do
      membership = insert(:membership, role: :admin)
      scope = build_scope(membership)

      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          visible: true,
          config: %{"headline" => "Visible"}
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

      view
      |> element("[data-test=toggle-visibility-#{section.id}]")
      |> render_click()

      {:ok, updated} = LandingPage.get_landing_section(membership.organization, section.id)
      assert updated.visible == false
    end
  end

  describe "reorder via move buttons" do
    test "moving down swaps positions" do
      membership = insert(:membership, role: :admin)
      scope = build_scope(membership)

      {:ok, first} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "First"}
        })

      {:ok, _second} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Second"}
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

      view
      |> element("[data-test=section-item-#{first.id}] button[phx-click=move_down]")
      |> render_click()

      %{results: sections} = LandingPage.list_landing_sections_admin(membership.organization)

      headlines =
        sections
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.config["headline"])

      assert headlines == ["Second", "First"]
    end
  end

  describe "multi-tenant isolation" do
    test "sections from another org are not visible" do
      membership = insert(:membership, role: :admin)
      other_org = insert(:organization)
      other_user = insert(:user)

      other_membership =
        insert(:membership, organization: other_org, user: other_user, role: :admin)

      other_scope = build_scope(other_membership)

      {:ok, foreign} =
        LandingPage.create_landing_section(other_scope, %{
          section_type: :header_text,
          config: %{"headline" => "Other Org Section"}
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/landing")

      refute has_element?(view, "[data-test=section-item-#{foreign.id}]")
      refute render(view) =~ "Other Org Section"
    end
  end
end
