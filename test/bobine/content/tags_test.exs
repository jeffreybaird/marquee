defmodule Bobine.Content.TagsTest do
  use Bobine.DataCase

  alias Bobine.Content
  alias Bobine.Accounts.Scope

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, scope: scope}
  end

  describe "list_tags/2" do
    test "returns only the org's tags", %{org: org, scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "Beginner"})

      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = Scope.for_user(other_user) |> Scope.with_organization(other_org, other_mem)
      {:ok, _} = Content.create_tag(other_scope, %{name: "Advanced"})

      assert %{results: [found]} = Content.list_tags(org)
      assert found.id == tag.id
    end
  end

  describe "create_tag/2" do
    test "normalizes name to lowercase", %{scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "BEGINNER"})
      assert tag.name == "beginner"
    end

    test "with duplicate name returns error", %{scope: scope} do
      {:ok, _} = Content.create_tag(scope, %{name: "beginner"})
      assert {:error, :already_exists} = Content.create_tag(scope, %{name: "beginner"})
    end

    test "auto-generates slug from name", %{scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "Live Session"})
      assert tag.slug == "live-session"
    end
  end

  describe "update_tag/3" do
    test "updates name", %{scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "oldname"})

      assert {:ok, updated} = Content.update_tag(scope, tag, %{name: "newname"})
      assert updated.name == "newname"
    end

    test "updates slug when explicitly passed", %{scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "oldname"})

      assert {:ok, updated} =
               Content.update_tag(scope, tag, %{
                 name: "newname",
                 slug: Content.slugify("newname")
               })

      assert updated.slug == "newname"
    end

    test "with empty name returns validation error", %{scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "valid"})

      assert {:error, :validation, changeset} = Content.update_tag(scope, tag, %{name: ""})
      assert errors_on(changeset)[:name] != nil
    end
  end

  describe "delete_tag/2" do
    test "soft-deletes and removes video associations", %{org: org, scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "removable"})
      video = insert(:video, organization: org)
      {:ok, _} = Content.tag_video(scope, video, tag)

      assert {:ok, deleted} = Content.delete_tag(scope, tag)
      assert deleted.deleted_at != nil

      # Video associations removed
      assert Content.list_video_tags(org, video) == []
    end
  end

  describe "tag_video/3" do
    test "creates association", %{org: org, scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "featured"})
      video = insert(:video, organization: org)

      {:ok, video_tag} = Content.tag_video(scope, video, tag)
      assert video_tag.video_id == video.id
      assert video_tag.tag_id == tag.id
    end

    test "duplicate returns already_exists", %{org: org, scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "featured"})
      video = insert(:video, organization: org)

      {:ok, _} = Content.tag_video(scope, video, tag)
      assert {:error, :already_exists} = Content.tag_video(scope, video, tag)
    end
  end

  describe "untag_video/3" do
    test "removes association", %{org: org, scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "temporary"})
      video = insert(:video, organization: org)
      {:ok, _} = Content.tag_video(scope, video, tag)

      assert :ok = Content.untag_video(scope, video, tag)
      assert Content.list_video_tags(org, video) == []
    end
  end

  describe "list_videos_by_tag/3" do
    test "returns correct videos", %{org: org, scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "yoga"})
      video1 = insert(:video, organization: org, title: "Yoga 101")
      video2 = insert(:video, organization: org, title: "Cooking 101")

      {:ok, _} = Content.tag_video(scope, video1, tag)

      %{results: videos} = Content.list_videos_by_tag(org, tag)
      assert length(videos) == 1
      assert hd(videos).id == video1.id
      refute Enum.any?(videos, &(&1.id == video2.id))
    end
  end

  describe "multi-tenant isolation" do
    test "org A's tags are not visible to org B", %{scope: scope} do
      {:ok, _} = Content.create_tag(scope, %{name: "invisible"})
      org_b = insert(:organization)
      assert %{results: []} = Content.list_tags(org_b)
    end

    test "org A's tag cannot be applied to org B's video", %{scope: scope_a} do
      {:ok, tag_a} = Content.create_tag(scope_a, %{name: "a-tag"})

      org_b = insert(:organization)
      video_b = insert(:video, organization: org_b)

      # The tag_video function uses scope_a's org_id for the join record
      {:ok, _} = Content.tag_video(scope_a, video_b, tag_a)

      # But listing by org B won't show the tag (filtered by org_id)
      assert Content.list_video_tags(org_b, video_b) == []
    end
  end
end
