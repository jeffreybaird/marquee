defmodule Bobine.BrandingTest do
  use Bobine.DataCase

  alias Bobine.Branding

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

    test "list_themes/1 returns themes for the given organization" do
      theme = theme_fixture()
      org = Bobine.Repo.get!(Bobine.Accounts.Organization, theme.organization_id)
      assert Branding.list_themes(org) == [theme]
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
end
