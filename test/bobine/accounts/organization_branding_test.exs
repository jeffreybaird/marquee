defmodule Bobine.Accounts.OrganizationBrandingTest do
  use Bobine.DataCase, async: true

  alias Bobine.Accounts
  alias Bobine.Accounts.Organization

  describe "update_organization_branding/2" do
    setup do
      %{org: insert(:organization)}
    end

    test "accepts oklch() accent values + approved display font", %{org: org} do
      attrs = %{
        preset_name: "learning_platform",
        accent_color_base: "oklch(0.62 0.18 250)",
        accent_color_hover: "oklch(0.68 0.18 250)",
        accent_color_active: "oklch(0.56 0.18 250)",
        accent_color_subtle: "oklch(0.26 0.08 250)",
        display_font: "DM Serif Display"
      }

      assert {:ok, updated} = Accounts.update_organization_branding(org, attrs)
      assert updated.preset_name == "learning_platform"
      assert updated.accent_color_base == "oklch(0.62 0.18 250)"
      assert updated.display_font == "DM Serif Display"
    end

    test "accepts hex accent values (backfill-compatible)", %{org: org} do
      attrs = %{accent_color_base: "#E50914"}
      assert {:ok, updated} = Accounts.update_organization_branding(org, attrs)
      assert updated.accent_color_base == "#E50914"
    end

    test "rejects non-color strings", %{org: org} do
      attrs = %{accent_color_base: "red"}

      assert {:error, :validation, cs} = Accounts.update_organization_branding(org, attrs)

      refute cs.valid?
      assert "must be an oklch() or hex color" in errors_on(cs).accent_color_base
    end

    test "rejects a display font outside the allowlist", %{org: org} do
      attrs = %{display_font: "Comic Sans"}

      assert {:error, :validation, cs} = Accounts.update_organization_branding(org, attrs)

      refute cs.valid?
      assert Map.has_key?(errors_on(cs), :display_font)
    end

    test "rejects an unknown preset name", %{org: org} do
      attrs = %{preset_name: "bogus"}

      assert {:error, :validation, cs} = Accounts.update_organization_branding(org, attrs)

      refute cs.valid?
      assert Map.has_key?(errors_on(cs), :preset_name)
    end

    test "allows clearing optional fields by omission", %{org: org} do
      assert {:ok, updated} = Accounts.update_organization_branding(org, %{})
      assert updated.id == org.id
    end
  end

  describe "broadcast" do
    setup do
      %{org: insert(:organization)}
    end

    test "successful update broadcasts organization_branding_updated on events topic",
         %{org: org} do
      Bobine.Events.subscribe(org.id)

      {:ok, updated} =
        Accounts.update_organization_branding(org, %{accent_color_base: "oklch(0.5 0.1 120)"})

      assert_receive {:bobine_event, {:organization_branding_updated, ^updated}, _scope}
    end

    test "validation failures do not broadcast", %{org: org} do
      Bobine.Events.subscribe(org.id)

      {:error, :validation, _cs} =
        Accounts.update_organization_branding(org, %{accent_color_base: "red"})

      refute_receive {:bobine_event, {:organization_branding_updated, _}, _}, 50
    end
  end

  describe "approved_display_fonts/0" do
    test "exposes the Google Fonts allowlist" do
      fonts = Organization.approved_display_fonts()
      assert "DM Serif Display" in fonts
      assert "Cormorant Garamond" in fonts
      refute "Comic Sans" in fonts
    end
  end
end
