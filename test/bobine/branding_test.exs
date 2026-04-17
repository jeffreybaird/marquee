defmodule Bobine.BrandingTest do
  use Bobine.DataCase

  alias Bobine.Branding
  alias Bobine.Branding.Theme

  defp seed_default_theme_for(org) do
    attrs = Theme.preset_attrs(Theme.default_preset_key()) |> Map.put(:organization_id, org.id)
    {:ok, theme} = Branding.create_theme(attrs)
    theme
  end

  describe "themes" do
    alias Bobine.Branding.Theme

    import Bobine.BrandingFixtures

    @invalid_attrs %{
      organization_id: nil,
      background: nil,
      accent: nil,
      brand_primary: nil,
      brand_secondary: nil,
      surface: nil,
      text_primary: nil,
      text_secondary: nil,
      font_heading: nil,
      font_body: nil,
      border_radius: nil,
      card_border_radius: nil,
      logo_url: nil,
      favicon_url: nil
    }

    setup do
      %{org: insert(:organization)}
    end

    test "list_themes/2 returns paginated themes for the organization" do
      theme = theme_fixture()
      org = Bobine.Repo.get!(Bobine.Accounts.Organization, theme.organization_id)
      assert %{results: [found], total: 1} = Branding.list_themes(org)
      assert found.id == theme.id
    end

    test "get_theme!/1 returns the theme with given id" do
      theme = theme_fixture()
      assert Branding.get_theme!(theme.id) == theme
    end

    test "create_theme/1 with valid data creates a theme", %{org: org} do
      valid_attrs = %{
        background: "some background",
        accent: "some accent",
        brand_primary: "some brand_primary",
        brand_secondary: "some brand_secondary",
        surface: "some surface",
        text_primary: "some text_primary",
        text_secondary: "some text_secondary",
        font_heading: "some font_heading",
        font_body: "some font_body",
        border_radius: "some border_radius",
        card_border_radius: "some card_border_radius",
        logo_url: "some logo_url",
        favicon_url: "some favicon_url",
        organization_id: org.id
      }

      assert {:ok, %Theme{} = theme} = Branding.create_theme(valid_attrs)
      assert theme.background == "some background"
      assert theme.accent == "some accent"
      assert theme.brand_primary == "some brand_primary"
      assert theme.brand_secondary == "some brand_secondary"
      assert theme.surface == "some surface"
      assert theme.text_primary == "some text_primary"
      assert theme.text_secondary == "some text_secondary"
      assert theme.font_heading == "some font_heading"
      assert theme.font_body == "some font_body"
      assert theme.border_radius == "some border_radius"
      assert theme.card_border_radius == "some card_border_radius"
      assert theme.logo_url == "some logo_url"
      assert theme.favicon_url == "some favicon_url"
    end

    test "create_theme/1 with invalid data returns error changeset" do
      assert {:error, :validation, %Ecto.Changeset{}} = Branding.create_theme(@invalid_attrs)
    end

    test "update_theme/2 with valid data updates the theme" do
      theme = theme_fixture()

      update_attrs = %{
        background: "some updated background",
        accent: "some updated accent",
        brand_primary: "some updated brand_primary",
        brand_secondary: "some updated brand_secondary",
        surface: "some updated surface",
        text_primary: "some updated text_primary",
        text_secondary: "some updated text_secondary",
        font_heading: "some updated font_heading",
        font_body: "some updated font_body",
        border_radius: "some updated border_radius",
        card_border_radius: "some updated card_border_radius",
        logo_url: "some updated logo_url",
        favicon_url: "some updated favicon_url"
      }

      assert {:ok, %Theme{} = theme} = Branding.update_theme(theme, update_attrs)
      assert theme.background == "some updated background"
      assert theme.accent == "some updated accent"
      assert theme.brand_primary == "some updated brand_primary"
      assert theme.brand_secondary == "some updated brand_secondary"
      assert theme.surface == "some updated surface"
      assert theme.text_primary == "some updated text_primary"
      assert theme.text_secondary == "some updated text_secondary"
      assert theme.font_heading == "some updated font_heading"
      assert theme.font_body == "some updated font_body"
      assert theme.border_radius == "some updated border_radius"
      assert theme.card_border_radius == "some updated card_border_radius"
      assert theme.logo_url == "some updated logo_url"
      assert theme.favicon_url == "some updated favicon_url"
    end

    test "update_theme/2 with invalid data returns error changeset" do
      theme = theme_fixture()

      assert {:error, :validation, %Ecto.Changeset{}} =
               Branding.update_theme(theme, @invalid_attrs)

      assert theme == Branding.get_theme!(theme.id)
    end

    test "delete_theme/1 deletes the theme" do
      theme = theme_fixture()
      assert {:ok, %Theme{}} = Branding.delete_theme(theme)
      assert_raise Ecto.NoResultsError, fn -> Branding.get_theme!(theme.id) end
    end

    test "change_theme/1 returns a theme changeset" do
      theme = theme_fixture()
      assert %Ecto.Changeset{} = Branding.change_theme(theme)
    end
  end

  describe "list_orgs_without_theme/0" do
    test "returns only orgs that have no theme" do
      with_theme = insert(:organization)
      seed_default_theme_for(with_theme)

      without_theme_a = insert(:organization)
      without_theme_b = insert(:organization)

      result_ids = Branding.list_orgs_without_theme() |> Enum.map(& &1.id)

      assert without_theme_a.id in result_ids
      assert without_theme_b.id in result_ids
      refute with_theme.id in result_ids
    end

    test "excludes soft-deleted organizations" do
      live_org = insert(:organization)

      deleted_org =
        insert(:organization)
        |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
        |> Bobine.Repo.update!()

      result_ids = Branding.list_orgs_without_theme() |> Enum.map(& &1.id)

      assert live_org.id in result_ids
      refute deleted_org.id in result_ids
    end
  end

  describe "backfill_missing_themes/1" do
    test "creates a theme for every org missing one using the default preset" do
      org_a = insert(:organization)
      org_b = insert(:organization)

      org_with_theme = insert(:organization)
      seed_default_theme_for(org_with_theme)

      assert {:ok, summary} = Branding.backfill_missing_themes()

      assert summary.created == 2
      assert summary.preset == Theme.default_preset_key()
      refute summary.dry_run?
      assert summary.failed == []

      created_org_ids = Enum.map(summary.orgs, & &1.id)
      assert org_a.id in created_org_ids
      assert org_b.id in created_org_ids
      refute org_with_theme.id in created_org_ids

      preset = Theme.preset_attrs(Theme.default_preset_key())

      for org <- [org_a, org_b] do
        theme = Branding.get_theme_by_org(org)
        assert theme.background == preset.background
        assert theme.brand_primary == preset.brand_primary
      end
    end

    test "applies the requested preset when one is supplied" do
      org = insert(:organization)

      assert {:ok, summary} = Branding.backfill_missing_themes(preset: "daybreak")
      assert summary.preset == "daybreak"
      assert summary.created == 1

      theme = Branding.get_theme_by_org(org)
      preset = Theme.preset_attrs("daybreak")
      assert theme.background == preset.background
      assert theme.brand_primary == preset.brand_primary
    end

    test "dry_run returns matching orgs without writing" do
      org = insert(:organization)

      assert {:ok, summary} = Branding.backfill_missing_themes(dry_run: true)
      assert summary.dry_run?
      assert summary.created == 0
      assert Enum.map(summary.orgs, & &1.id) |> Enum.member?(org.id)

      assert Branding.get_theme_by_org(org) == nil
    end

    test "is idempotent — running twice does not create duplicate themes" do
      insert(:organization)

      {:ok, first} = Branding.backfill_missing_themes()
      {:ok, second} = Branding.backfill_missing_themes()

      assert first.created == 1
      assert second.created == 0
      assert second.orgs == []
    end

    test "returns {:error, :unknown_preset} for an invalid preset key" do
      assert Branding.backfill_missing_themes(preset: "neon-rainbow") ==
               {:error, :unknown_preset}
    end

    test "returns an empty summary when no orgs need backfilling" do
      org = insert(:organization)
      seed_default_theme_for(org)

      assert {:ok, summary} = Branding.backfill_missing_themes()
      assert summary.created == 0
      assert summary.orgs == []
      assert summary.failed == []
    end
  end
end
