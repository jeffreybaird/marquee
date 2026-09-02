defmodule MarqueeWeb.Admin.DashboardNudgesTest do
  use ExUnit.Case, async: true

  alias MarqueeWeb.Admin.DashboardNudges

  doctest MarqueeWeb.Admin.DashboardNudges

  @all_complete %{
    stripe_connected: true,
    has_plans: true,
    has_theme: true,
    has_catalog_rows: true
  }

  describe "active/2" do
    test "returns no nudges when every setup step is complete" do
      assert DashboardNudges.active(@all_complete, []) == []
    end

    test "surfaces a nudge for each incomplete step" do
      conditions = %{@all_complete | stripe_connected: false, has_theme: false}

      keys = DashboardNudges.active(conditions, []) |> Enum.map(& &1.key)

      assert keys == ["connect_stripe", "customize_branding"]
    end

    test "a dismissed key is suppressed even while its step is incomplete" do
      conditions = %{@all_complete | stripe_connected: false}

      assert DashboardNudges.active(conditions, ["connect_stripe"]) == []
    end

    test "a missing condition key is treated as incomplete" do
      keys = DashboardNudges.active(%{}, []) |> Enum.map(& &1.key)

      assert keys == Enum.map(DashboardNudges.catalog(), & &1.key)
    end

    test "every nudge carries a title, body, cta label, and cta path" do
      conditions = %{
        stripe_connected: false,
        has_plans: false,
        has_theme: false,
        has_catalog_rows: false
      }

      for nudge <- DashboardNudges.active(conditions, []) do
        assert is_binary(nudge.title) and nudge.title != ""
        assert is_binary(nudge.body) and nudge.body != ""
        assert is_binary(nudge.cta_label) and nudge.cta_label != ""
        assert String.starts_with?(nudge.cta_path, "/admin/")
      end
    end
  end
end
