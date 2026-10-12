defmodule MarqueeWeb.Admin.ShortsLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.Content
  alias Marquee.Repo

  # Event contract for forced (non-UI) submissions used by the read-only
  # checks below:
  #   "toggle_enabled"  %{}
  #   "set_access"      %{"access" => level}
  #   "open_picker"     %{}
  #   "add_video"       %{"video-id" => video_id}
  #   "remove_item"     %{"id" => item_id}
  #   "move_item"       %{"id" => item_id, "direction" => "up" | "down"}

  defp member(org, role) do
    insert(:membership, organization: org, user: insert(:user), role: role)
  end

  defp editor_scope(org) do
    membership = member(org, :editor) |> Repo.preload([:user, :organization])
    Scope.for_user(membership.user) |> Scope.with_organization(org, membership)
  end

  defp ready_video(org, attrs \\ []) do
    insert(
      :video,
      Keyword.merge(
        [organization: org, mux_status: "ready", duration: 42.0, aspect_ratio: "9:16"],
        attrs
      )
    )
  end

  defp feed_ids(org) do
    org
    |> Content.list_short_feed_items(per_page: 100)
    |> Map.fetch!(:results)
    |> Enum.map(& &1.video_id)
  end

  defp reload_org(org), do: Repo.get!(Organization, org.id)

  defp sel(test_id), do: ~s([data-test="#{test_id}"])

  setup do
    org =
      insert(:organization, shorts_feed_enabled: false, shorts_feed_access: "subscribers_only")

    %{org: org}
  end

  describe "navigation" do
    test "Shorts nav link is shown and marked current on /admin/shorts", %{org: org} do
      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")

      assert has_element?(view, ~s([data-test="admin-nav-shorts"][aria-current="page"]))
      assert has_element?(view, ~s([data-test="admin-nav-shorts"][href="/admin/shorts"]))
    end

    test "Shorts nav link is not current on another admin page", %{org: org} do
      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/collections")

      assert has_element?(view, sel("admin-nav-shorts"))
      refute has_element?(view, ~s([data-test="admin-nav-shorts"][aria-current="page"]))
    end
  end

  describe "empty state" do
    test "shows an empty state when the feed has no items", %{org: org} do
      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")
      assert has_element?(view, sel("shorts-admin-empty"))
    end
  end

  for role <- [:owner, :admin, :editor] do
    describe "#{role} management" do
      @role role

      test "can switch the feed on and off", %{org: org} do
        {:ok, view, _html} = live(conn_for(member(org, @role)), ~p"/admin/shorts")

        assert has_element?(
                 view,
                 ~s([data-test="shorts-enabled-toggle"][role="switch"][aria-checked="false"])
               )

        view |> element(sel("shorts-enabled-toggle")) |> render_click()

        assert has_element?(view, ~s([data-test="shorts-enabled-toggle"][aria-checked="true"]))
        assert reload_org(org).shorts_feed_enabled == true

        view |> element(sel("shorts-enabled-toggle")) |> render_click()
        assert reload_org(org).shorts_feed_enabled == false
      end

      test "can choose the access level", %{org: org} do
        {:ok, view, _html} = live(conn_for(member(org, @role)), ~p"/admin/shorts")

        assert has_element?(view, sel("shorts-access-select"))

        for level <- ["public", "free_with_account", "subscribers_only"] do
          view |> form(sel("shorts-access-form"), %{"access" => level}) |> render_change()
          assert reload_org(org).shorts_feed_access == level
        end
      end

      test "can add an eligible video from the picker", %{org: org} do
        video = ready_video(org, title: "Picker Pick")
        {:ok, view, _html} = live(conn_for(member(org, @role)), ~p"/admin/shorts")

        view |> element(sel("shorts-open-picker")) |> render_click()
        assert has_element?(view, sel("shorts-picker-video-#{video.id}"))

        view |> element(sel("shorts-add-#{video.id}")) |> render_click()

        assert feed_ids(org) == [video.id]
        [item] = Content.list_short_feed_items(org).results
        assert has_element?(view, sel("shorts-item-#{item.id}"), "Picker Pick")
        refute has_element?(view, sel("shorts-admin-empty"))
      end

      test "can remove an item", %{org: org} do
        scope = editor_scope(org)
        v1 = ready_video(org, title: "Keep Me")
        v2 = ready_video(org, title: "Drop Me")
        {:ok, _} = Content.add_short_feed_video(scope, v1)
        {:ok, i2} = Content.add_short_feed_video(scope, v2)

        {:ok, view, _html} = live(conn_for(member(org, @role)), ~p"/admin/shorts")
        view |> element(sel("shorts-remove-#{i2.id}")) |> render_click()

        assert feed_ids(org) == [v1.id]
        refute has_element?(view, sel("shorts-item-#{i2.id}"))
      end

      test "can move items up and down", %{org: org} do
        scope = editor_scope(org)
        [v1, v2, v3] = for n <- 1..3, do: ready_video(org, title: "Clip #{n}")
        [_i1, i2, i3] = Enum.map([v1, v2, v3], &elem(Content.add_short_feed_video(scope, &1), 1))

        {:ok, view, _html} = live(conn_for(member(org, @role)), ~p"/admin/shorts")

        view |> element(sel("shorts-move-up-#{i3.id}")) |> render_click()
        assert feed_ids(org) == [v1.id, v3.id, v2.id]

        view |> element(sel("shorts-move-down-#{i2.id}")) |> render_click()
        assert feed_ids(org) == [v1.id, v3.id, v2.id]

        html = render(view)
        {p1, _} = :binary.match(html, "Clip 1")
        {p3, _} = :binary.match(html, "Clip 3")
        {p2, _} = :binary.match(html, "Clip 2")
        assert p1 < p3 and p3 < p2
      end
    end
  end

  describe "row details" do
    test "rows show title, orientation, duration and status", %{org: org} do
      scope = editor_scope(org)
      tall = ready_video(org, title: "Tall One", aspect_ratio: "9:16", duration: 65.0)
      wide = ready_video(org, title: "Wide One", aspect_ratio: "16:9")
      {:ok, tall_item} = Content.add_short_feed_video(scope, tall)
      {:ok, wide_item} = Content.add_short_feed_video(scope, wide)

      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")

      assert has_element?(view, sel("shorts-item-#{tall_item.id}"), "Tall One")
      assert has_element?(view, sel("shorts-item-orientation-#{tall_item.id}"), "Portrait")
      assert has_element?(view, sel("shorts-item-orientation-#{wide_item.id}"), "Landscape")
      assert has_element?(view, sel("shorts-item-#{tall_item.id}"), "1:05")
      assert has_element?(view, sel("shorts-item-status-#{tall_item.id}"), "Ready")
    end

    test "an item whose video errored is badged Unavailable", %{org: org} do
      scope = editor_scope(org)
      video = ready_video(org, title: "Gone Bad")
      {:ok, item} = Content.add_short_feed_video(scope, video)
      {:ok, _} = Content.mark_video_errored(video.mux_asset_id, %{})

      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")

      assert has_element?(view, sel("shorts-item-#{item.id}"), "Gone Bad")
      assert has_element?(view, sel("shorts-item-status-#{item.id}"), "Unavailable")
    end

    test "move and remove controls are labelled buttons", %{org: org} do
      scope = editor_scope(org)
      {:ok, item} = Content.add_short_feed_video(scope, ready_video(org))

      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")

      for id <- [
            "shorts-move-up-#{item.id}",
            "shorts-move-down-#{item.id}",
            "shorts-remove-#{item.id}"
          ] do
        assert has_element?(view, ~s(button[data-test="#{id}"][aria-label]))
      end
    end
  end

  describe "access level control" do
    test "every access input has a linked label", %{org: org} do
      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")

      inputs =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(~s([data-test="shorts-access-form"] [name="access"]))

      ids = LazyHTML.attribute(inputs, "id")

      refute Enum.empty?(inputs)
      assert length(ids) == Enum.count(inputs), "every access input needs an id"

      for id <- ids do
        assert is_binary(id) and id != ""
        assert has_element?(view, ~s(label[for="#{id}"]))
      end
    end
  end

  describe "picker eligibility" do
    test "offers only eligible videos from this organization", %{org: org} do
      scope = editor_scope(org)
      eligible = ready_video(org, title: "Eligible")
      in_feed = ready_video(org, title: "Already Added")
      {:ok, _} = Content.add_short_feed_video(scope, in_feed)
      processing = ready_video(org, title: "Still Processing", mux_status: "preparing")
      errored = ready_video(org, title: "Errored Encode", mux_status: "errored")

      deleted =
        ready_video(org,
          title: "Deleted Clip",
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      no_playback = ready_video(org, title: "No Playback", mux_playback_id: nil)
      foreign = ready_video(insert(:organization), title: "Rival Org Video")

      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")
      view |> element(sel("shorts-open-picker")) |> render_click()

      assert has_element?(view, sel("shorts-picker-video-#{eligible.id}"))

      for video <- [in_feed, processing, errored, deleted, no_playback, foreign] do
        refute has_element?(view, sel("shorts-picker-video-#{video.id}"))
        refute has_element?(view, sel("shorts-add-#{video.id}"))
      end

      refute render(view) =~ "Rival Org Video"
    end

    test "search narrows the picker", %{org: org} do
      alpha = ready_video(org, title: "Alpha Dance")
      beta = ready_video(org, title: "Beta Cooking")

      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")
      view |> element(sel("shorts-open-picker")) |> render_click()

      view |> form(sel("shorts-picker-search"), %{"search" => "alpha"}) |> render_change()

      assert has_element?(view, sel("shorts-picker-video-#{alpha.id}"))
      refute has_element?(view, sel("shorts-picker-video-#{beta.id}"))
    end

    test "a forced add of another organization's video changes nothing", %{org: org} do
      foreign = ready_video(insert(:organization))
      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")

      render_click(view, "add_video", %{"video-id" => foreign.id})

      assert feed_ids(org) == []
      assert has_element?(view, "#flash-error")
    end
  end

  describe "viewer_support" do
    setup %{org: org} do
      scope = editor_scope(org)
      v1 = ready_video(org, title: "First Clip")
      v2 = ready_video(org, title: "Second Clip")
      {:ok, i1} = Content.add_short_feed_video(scope, v1)
      {:ok, i2} = Content.add_short_feed_video(scope, v2)
      candidate = ready_video(org, title: "Candidate")
      %{v1: v1, v2: v2, i1: i1, i2: i2, candidate: candidate}
    end

    test "sees the feed read-only with no controls", ctx do
      {:ok, view, _html} = live(conn_for(member(ctx.org, :viewer_support)), ~p"/admin/shorts")

      assert has_element?(view, sel("shorts-item-#{ctx.i1.id}"), "First Clip")
      assert has_element?(view, sel("shorts-item-#{ctx.i2.id}"), "Second Clip")

      for id <- [
            "shorts-enabled-toggle",
            "shorts-access-select",
            "shorts-access-form",
            "shorts-open-picker",
            "shorts-remove-#{ctx.i1.id}",
            "shorts-move-up-#{ctx.i2.id}",
            "shorts-move-down-#{ctx.i1.id}"
          ] do
        refute has_element?(view, sel(id)), "expected no #{id} control"
      end
    end

    test "forced events are refused with a flash and change nothing", ctx do
      forced = [
        fn view -> render_click(view, "toggle_enabled", %{}) end,
        fn view -> render_change(view, "set_access", %{"access" => "public"}) end,
        fn view -> render_click(view, "open_picker", %{}) end,
        fn view -> render_click(view, "add_video", %{"video-id" => ctx.candidate.id}) end,
        fn view -> render_click(view, "remove_item", %{"id" => ctx.i1.id}) end,
        fn view -> render_click(view, "move_item", %{"id" => ctx.i2.id, "direction" => "up"}) end
      ]

      conn = conn_for(member(ctx.org, :viewer_support))

      for push <- forced do
        # A fresh mount per event so each refusal must raise its own flash.
        {:ok, view, _html} = live(conn, ~p"/admin/shorts")
        refute has_element?(view, "#flash-error")
        push.(view)
        assert has_element?(view, "#flash-error")
        refute has_element?(view, sel("shorts-picker-video-#{ctx.candidate.id}"))
      end

      org = reload_org(ctx.org)
      assert org.shorts_feed_enabled == false
      assert org.shorts_feed_access == "subscribers_only"
      assert feed_ids(ctx.org) == [ctx.v1.id, ctx.v2.id]
    end
  end

  describe "unsupported move direction" do
    test "a forced sideways move is refused with a flash and changes nothing", %{org: org} do
      scope = editor_scope(org)
      [v1, v2] = for n <- 1..2, do: ready_video(org, title: "Side #{n}")
      [_i1, i2] = Enum.map([v1, v2], &elem(Content.add_short_feed_video(scope, &1), 1))

      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")
      render_click(view, "move_item", %{"id" => i2.id, "direction" => "sideways"})

      assert has_element?(view, "#flash-error")
      assert feed_ids(org) == [v1.id, v2.id]
      # Still alive and responsive.
      assert has_element?(view, sel("shorts-item-#{i2.id}"), "Side 2")
      view |> element(sel("shorts-move-up-#{i2.id}")) |> render_click()
      assert feed_ids(org) == [v2.id, v1.id]
    end
  end

  describe "tenant isolation" do
    test "never lists another organization's feed items", %{org: org} do
      other = insert(:organization)
      other_scope = editor_scope(other)

      {:ok, theirs} =
        Content.add_short_feed_video(other_scope, ready_video(other, title: "Theirs"))

      {:ok, view, html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")

      refute html =~ "Theirs"
      refute has_element?(view, sel("shorts-item-#{theirs.id}"))
      assert has_element?(view, sel("shorts-admin-empty"))
    end

    test "a forced remove of another organization's item changes nothing", %{org: org} do
      other = insert(:organization)
      other_scope = editor_scope(other)
      video = ready_video(other)
      {:ok, theirs} = Content.add_short_feed_video(other_scope, video)

      {:ok, view, _html} = live(conn_for(member(org, :editor)), ~p"/admin/shorts")
      render_click(view, "remove_item", %{"id" => theirs.id})

      assert feed_ids(other) == [video.id]
      assert has_element?(view, "#flash-error")
    end
  end
end
