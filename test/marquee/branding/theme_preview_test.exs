defmodule Marquee.Branding.ThemePreviewTest do
  use Marquee.DataCase, async: true

  alias Marquee.Branding
  alias Marquee.Branding.Theme
  alias Marquee.Cache

  defp draft(attrs \\ %{}) do
    Map.merge(
      %{
        theme: %Theme{background: "#123456", surface: "#1A1A1A"},
        accent_color_base: "#ABCDEF",
        display_font: "Playfair Display"
      },
      attrs
    )
  end

  describe "put_theme_preview/3 and get_theme_preview/2" do
    test "round-trips an unsaved draft for an organization" do
      org = insert(:organization)
      preview_id = Ecto.UUID.generate()
      draft = draft()

      assert :ok = Branding.put_theme_preview(org, preview_id, draft)
      assert Branding.get_theme_preview(org, preview_id) == draft
    end

    test "stores the draft under an org-scoped cache key" do
      org = insert(:organization)
      preview_id = Ecto.UUID.generate()
      draft = draft()

      :ok = Branding.put_theme_preview(org, preview_id, draft)

      assert Cache.get("theme_preview:#{org.id}:#{preview_id}") == {:ok, draft}
    end

    test "overwrites an earlier draft with the same preview id" do
      org = insert(:organization)
      preview_id = Ecto.UUID.generate()

      :ok = Branding.put_theme_preview(org, preview_id, draft())
      :ok = Branding.put_theme_preview(org, preview_id, draft(%{accent_color_base: "#000000"}))

      assert %{accent_color_base: "#000000"} = Branding.get_theme_preview(org, preview_id)
    end

    test "returns nil when no draft exists for the preview id" do
      org = insert(:organization)

      assert Branding.get_theme_preview(org, Ecto.UUID.generate()) == nil
    end

    test "returns nil for a nil preview id" do
      org = insert(:organization)

      assert Branding.get_theme_preview(org, nil) == nil
    end

    test "a draft stored for one organization is not returned for another" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      preview_id = Ecto.UUID.generate()

      :ok = Branding.put_theme_preview(org_a, preview_id, draft())

      assert Branding.get_theme_preview(org_a, preview_id) == draft()
      assert Branding.get_theme_preview(org_b, preview_id) == nil
    end
  end

  describe "clear_theme_preview/2" do
    test "removes the draft so a later read returns nil" do
      org = insert(:organization)
      preview_id = Ecto.UUID.generate()

      :ok = Branding.put_theme_preview(org, preview_id, draft())
      assert :ok = Branding.clear_theme_preview(org, preview_id)
      assert Branding.get_theme_preview(org, preview_id) == nil
    end

    test "only clears the draft for the given organization" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      preview_id = Ecto.UUID.generate()

      :ok = Branding.put_theme_preview(org_a, preview_id, draft())
      :ok = Branding.put_theme_preview(org_b, preview_id, draft(%{accent_color_base: "#000000"}))

      :ok = Branding.clear_theme_preview(org_a, preview_id)

      assert Branding.get_theme_preview(org_a, preview_id) == nil
      assert %{accent_color_base: "#000000"} = Branding.get_theme_preview(org_b, preview_id)
    end

    test "is a no-op when nothing is stored" do
      org = insert(:organization)

      assert :ok = Branding.clear_theme_preview(org, Ecto.UUID.generate())
    end
  end
end
