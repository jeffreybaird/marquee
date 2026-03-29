defmodule Bobine.FeaturesTest do
  use Bobine.DataCase, async: true

  alias Bobine.Features
  alias Bobine.Accounts.Organization

  describe "enabled?/2" do
    test "returns true when feature is set to true" do
      org = %Organization{features: %{"live_streaming" => true}}
      assert Features.enabled?(org, :live_streaming)
    end

    test "returns false when feature is missing" do
      org = %Organization{features: %{}}
      refute Features.enabled?(org, :live_streaming)
    end

    test "returns false when features map is nil" do
      org = %Organization{features: nil}
      refute Features.enabled?(org, :live_streaming)
    end

    test "returns false when feature is set to false" do
      org = %Organization{features: %{"analytics" => false}}
      refute Features.enabled?(org, :analytics)
    end
  end

  describe "list_enabled/1" do
    test "returns only enabled feature names" do
      org = %Organization{
        features: %{"live_streaming" => true, "analytics" => false, "drm" => true}
      }

      result = Features.list_enabled(org) |> Enum.sort()
      assert result == ["drm", "live_streaming"]
    end

    test "returns empty list when no features enabled" do
      org = %Organization{features: %{}}
      assert Features.list_enabled(org) == []
    end

    test "returns empty list when features is nil" do
      org = %Organization{features: nil}
      assert Features.list_enabled(org) == []
    end
  end
end
