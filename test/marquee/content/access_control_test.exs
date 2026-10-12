defmodule Marquee.Content.AccessControlTest do
  use Marquee.DataCase

  alias Marquee.Content.AccessControl

  describe "can_watch?/2" do
    test "public video is accessible with nil viewer" do
      video = %{visibility: "public"}
      assert AccessControl.can_watch?(video, nil)
    end

    test "public video is accessible with any viewer" do
      video = %{visibility: "public"}
      viewer = build(:viewer, subscription_status: "none")
      assert AccessControl.can_watch?(video, viewer)
    end

    test "free_with_account video is accessible with any viewer" do
      video = %{visibility: "free_with_account"}
      viewer = build(:viewer, subscription_status: "none")
      assert AccessControl.can_watch?(video, viewer)
    end

    test "free_with_account video is not accessible with nil viewer" do
      video = %{visibility: "free_with_account"}
      refute AccessControl.can_watch?(video, nil)
    end

    test "subscribers_only video is accessible with active subscriber" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:subscribed_viewer)
      assert AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with no subscription" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:viewer, subscription_status: "none")
      refute AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with nil viewer" do
      video = %{visibility: "subscribers_only"}
      refute AccessControl.can_watch?(video, nil)
    end

    test "subscribers_only video is accessible with past_due subscriber" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:viewer, subscription_status: "past_due")
      assert AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with canceled subscription" do
      video = %{visibility: "subscribers_only"}
      viewer = build(:viewer, subscription_status: "canceled")
      refute AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is accessible with active trial" do
      video = %{visibility: "subscribers_only"}

      viewer =
        build(:viewer,
          subscription_status: "trial",
          trial_expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
        )

      assert AccessControl.can_watch?(video, viewer)
    end

    test "subscribers_only video is not accessible with expired trial" do
      video = %{visibility: "subscribers_only"}

      viewer =
        build(:viewer,
          subscription_status: "trial",
          trial_expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        )

      refute AccessControl.can_watch?(video, viewer)
    end
  end

  describe "feed_access/2" do
    alias Marquee.Accounts.Scope
    alias Marquee.Viewers

    defp future, do: DateTime.add(DateTime.utc_now(), 7, :day)
    defp past, do: DateTime.add(DateTime.utc_now(), -1, :day)

    defp feed_viewer(nil), do: nil
    defp feed_viewer(:none), do: build(:viewer, subscription_status: "none")
    defp feed_viewer(:active), do: build(:viewer, subscription_status: "active")

    defp feed_viewer(:trial_valid),
      do: build(:viewer, subscription_status: "trial", trial_expires_at: future())

    defp feed_viewer(:trial_expired),
      do: build(:viewer, subscription_status: "trial", trial_expires_at: past())

    defp feed_viewer(:past_due), do: build(:viewer, subscription_status: "past_due")
    defp feed_viewer(:canceled), do: build(:viewer, subscription_status: "canceled")
    defp feed_viewer(:expired), do: build(:viewer, subscription_status: "expired")

    defp feed_viewer(:suspended),
      do: build(:viewer, subscription_status: "active", status: :suspended)

    defp feed_viewer(:banned), do: build(:viewer, subscription_status: "active", status: :banned)

    defp feed_viewer(:complimentary) do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :owner)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      {:ok, granted} = Viewers.grant_access(scope, viewer)
      granted
    end

    @expectations %{
      "public" => %{
        nil => :playable,
        none: :playable,
        active: :playable,
        complimentary: :playable,
        trial_valid: :playable,
        trial_expired: :playable,
        past_due: :playable,
        canceled: :playable,
        expired: :playable,
        suspended: {:locked, :suspended},
        banned: {:locked, :suspended}
      },
      "free_with_account" => %{
        nil => {:locked, :login},
        none: :playable,
        active: :playable,
        complimentary: :playable,
        trial_valid: :playable,
        trial_expired: :playable,
        past_due: :playable,
        canceled: :playable,
        expired: :playable,
        suspended: {:locked, :suspended},
        banned: {:locked, :suspended}
      },
      "subscribers_only" => %{
        nil => {:locked, :login},
        none: {:locked, :subscribe},
        active: :playable,
        complimentary: :playable,
        trial_valid: :playable,
        trial_expired: {:locked, :subscribe},
        past_due: {:locked, :payment_issue},
        canceled: {:locked, :subscribe},
        expired: {:locked, :subscribe},
        suspended: {:locked, :suspended},
        banned: {:locked, :suspended}
      }
    }

    for {level, cases} <- @expectations, {state, expected} <- cases do
      @level level
      @state state
      @expected expected

      test "#{level} feed with #{inspect(state)} viewer is #{inspect(expected)}" do
        viewer = feed_viewer(@state)
        assert AccessControl.feed_access(@level, viewer) == @expected
      end
    end

    test "feed level ignores the video's own visibility because it takes no video" do
      # A logged-out visitor can play everything in a public feed and nothing
      # in a subscribers-only feed, regardless of any per-video setting.
      assert AccessControl.feed_access("public", nil) == :playable
      assert AccessControl.feed_access("subscribers_only", nil) == {:locked, :login}
    end
  end
end
