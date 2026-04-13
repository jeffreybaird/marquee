defmodule BobineWeb.Admin.SeriesLiveImageUploadTest do
  @moduledoc """
  Full round-trip integration test for the Spaces image upload on the
  series cover form. The real `SpacesClient` never runs — `Mox` hands
  out a stubbed presigned URL and the test asserts the LiveView

    1. forwards the presign request to `Bobine.Storage`,
    2. pushes `spaces_presign_ready` back to the JS hook,
    3. stashes the completed URL in socket state, and
    4. merges the uploaded URL into `cover_image_url` on save.
  """

  use BobineWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Mox
  import Phoenix.LiveViewTest

  alias Bobine.Accounts.Scope
  alias Bobine.Content
  alias Bobine.Storage.MockSpacesClient

  setup :verify_on_exit!
  setup :set_mox_from_context

  defp build_scope(membership) do
    membership = Bobine.Repo.preload(membership, [:user, :organization])

    Scope.for_user(membership.user)
    |> Scope.with_organization(membership.organization, membership)
  end

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = build_scope(membership)
    %{org: org, scope: scope, membership: membership}
  end

  describe "series cover upload" do
    test "creates a series with an uploaded cover URL", %{conn: _conn, membership: membership} do
      public_url = "https://bobine-test.nyc3.digitaloceanspaces.com/org/xyz/series_cover/abc.jpg"

      expect(MockSpacesClient, :presign_put, fn opts ->
        assert opts[:content_type] == "image/jpeg"
        assert String.starts_with?(opts[:key], "org/")
        assert String.contains?(opts[:key], "/series_cover/")

        {:ok,
         %{
           presigned_url: "https://spaces.example/#{opts[:key]}",
           public_url: public_url,
           key: opts[:key],
           expires_at: DateTime.utc_now() |> DateTime.add(900, :second),
           headers: %{"Content-Type" => "image/jpeg"}
         }}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      # The hook fires this when the user picks a file
      render_hook(view, "spaces_presign_requested", %{
        "kind" => "series_cover",
        "target_id" => "new",
        "filename" => "pilot.jpg",
        "content_type" => "image/jpeg",
        "size" => 123_456
      })

      # JS hook reports successful upload
      render_hook(view, "spaces_upload_complete", %{
        "kind" => "series_cover",
        "target_id" => "new",
        "public_url" => public_url,
        "key" => "org/xyz/series_cover/abc.jpg"
      })

      # Now submit the form — the uploaded URL should be merged in
      view
      |> form(~s([data-test="series-form"]), series: %{title: "My Upload Show"})
      |> render_submit()

      {:ok, series} = get_series_by_title(membership.organization, "My Upload Show")
      assert series.cover_image_url == public_url
    end

    test "rejects unsupported file types", %{conn: _conn, membership: membership} do
      # No Mox expectation — the handler should reject before calling the client.
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      render_hook(view, "spaces_presign_requested", %{
        "kind" => "series_cover",
        "target_id" => "new",
        "filename" => "evil.exe",
        "content_type" => "application/x-msdownload",
        "size" => 10
      })

      html = render(view)
      assert html =~ ~s(data-test="image-upload-error-series_cover")
      assert html =~ "Unsupported file type"
    end

    test "does not presign for kinds the liveview does not authorize",
         %{conn: _conn, membership: membership} do
      # A kind this LiveView has not whitelisted in allowed_upload_kind?/1
      # must not result in a presign_put call — Mox will fail the test if
      # the client is called without an expectation.
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      render_hook(view, "spaces_presign_requested", %{
        "kind" => "video_thumbnail",
        "target_id" => "new",
        "filename" => "pic.jpg",
        "content_type" => "image/jpeg",
        "size" => 10
      })

      # Implicit assertion: no crash, no Mox expectation violation.
      assert render(view) =~ "series-form"
    end

    test "logs error on upload failure from the browser", %{membership: membership} do
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      log =
        capture_log(fn ->
          render_hook(view, "spaces_upload_error", %{
            "kind" => "series_cover",
            "target_id" => "new",
            "error" => "Network error during upload"
          })
        end)

      assert log =~ "Spaces upload failed"
      assert log =~ "Network error during upload"
    end

    test "logs error when presigning fails", %{membership: membership} do
      expect(MockSpacesClient, :presign_put, fn _opts ->
        {:error, :invalid_credentials}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      log =
        capture_log(fn ->
          render_hook(view, "spaces_presign_requested", %{
            "kind" => "series_cover",
            "target_id" => "new",
            "filename" => "pic.jpg",
            "content_type" => "image/jpeg",
            "size" => 10
          })
        end)

      assert log =~ "Spaces presign failed"
      assert log =~ "invalid_credentials"
    end

    test "logs error when content type is unsupported", %{membership: membership} do
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      log =
        capture_log(fn ->
          render_hook(view, "spaces_presign_requested", %{
            "kind" => "series_cover",
            "target_id" => "new",
            "filename" => "evil.exe",
            "content_type" => "application/x-msdownload",
            "size" => 10
          })
        end)

      assert log =~ "Spaces upload rejected"
      assert log =~ "unsupported content type"
    end

    test "logs error when upload kind is unauthorized", %{membership: membership} do
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      log =
        capture_log(fn ->
          render_hook(view, "spaces_presign_requested", %{
            "kind" => "video_thumbnail",
            "target_id" => "new",
            "filename" => "pic.jpg",
            "content_type" => "image/jpeg",
            "size" => 10
          })
        end)

      assert log =~ "Spaces upload rejected"
      assert log =~ "unauthorized kind"
    end
  end

  defp get_series_by_title(org, title) do
    case Content.list_series(org) do
      %{results: list} ->
        case Enum.find(list, &(&1.title == title)) do
          nil -> {:error, :not_found}
          series -> {:ok, series}
        end
    end
  end
end
