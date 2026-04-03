defmodule Bobine.PlatformBilling.EnforcementTest do
  use Bobine.DataCase, async: true

  import Mox

  alias Bobine.Accounts.Scope
  alias Bobine.Billing.PlatformSubscription
  alias Bobine.Content
  alias Bobine.Content.MockMuxClient

  setup :verify_on_exit!

  describe "Content.create_upload_url/2 enforces video limit" do
    test "returns plan_limit_reached when at video limit" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 1)
      insert(:platform_subscription, organization: org, platform_plan: plan)
      insert(:video, organization: org)

      user = insert(:user)
      scope = %Scope{user: user, organization: org}

      result = Content.create_upload_url(scope, %{title: "Over limit"})
      assert {:error, :plan_limit_reached, status} = result
      assert status.reached == true
      assert status.current == 1
      assert status.limit == 1
    end

    test "allows upload when under limit" do
      org = insert(:organization)
      plan = insert(:platform_plan, max_videos: 50)
      insert(:platform_subscription, organization: org, platform_plan: plan)

      user = insert(:user)
      scope = %Scope{user: user, organization: org}

      # Mock Mux client for successful upload
      expect(MockMuxClient, :create_direct_upload, fn _params ->
        {:ok, %{"id" => "upload_123", "url" => "https://mux.com/upload"}}
      end)

      assert {:ok, %{video: _video, upload_url: _url}} =
               Content.create_upload_url(scope, %{title: "Under limit"})
    end

    test "after upgrading plan, previously blocked action succeeds" do
      org = insert(:organization)
      small_plan = insert(:platform_plan, max_videos: 1, slug: "small")
      sub = insert(:platform_subscription, organization: org, platform_plan: small_plan)
      insert(:video, organization: org)

      user = insert(:user)
      scope = %Scope{user: user, organization: org}

      # Blocked at limit
      assert {:error, :plan_limit_reached, _} =
               Content.create_upload_url(scope, %{title: "Blocked"})

      # Upgrade plan
      big_plan =
        insert(:platform_plan,
          max_videos: 1000,
          slug: "big",
          usage_tier: :super,
          business_tier: :small_business
        )

      sub
      |> PlatformSubscription.changeset(%{platform_plan_id: big_plan.id})
      |> Repo.update!()

      # Now the upload should succeed
      expect(MockMuxClient, :create_direct_upload, fn _params ->
        {:ok, %{"id" => "upload_456", "url" => "https://mux.com/upload"}}
      end)

      assert {:ok, %{video: _video, upload_url: _url}} =
               Content.create_upload_url(scope, %{title: "Unblocked"})
    end
  end
end
