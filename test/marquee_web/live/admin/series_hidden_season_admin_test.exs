defmodule MarqueeWeb.Admin.SeriesHiddenSeasonAdminTest do
  @moduledoc """
  Guard for the D2 fix: hiding seasons from viewers must not hide them from
  operators. A hidden season stays listed in the admin series detail so it
  can be made visible again.
  """
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.Content

  defp setup_editor do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    membership = Marquee.Repo.preload(membership, [:user, :organization])

    scope =
      Scope.for_user(membership.user)
      |> Scope.with_organization(membership.organization, membership)

    %{org: org, membership: membership, scope: scope}
  end

  test "hidden season remains listed for the operator and can be re-shown" do
    %{org: org, membership: membership, scope: scope} = setup_editor()

    {:ok, series} = Content.create_series(scope, %{title: "Ops Series"})
    {:ok, hidden} = Content.create_season(scope, series, %{title: "Hidden One", visible: false})
    {:ok, shown} = Content.create_season(scope, series, %{title: "Shown Two", visible: true})

    {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
    view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()

    assert has_element?(view, ~s([data-test="season-row-#{hidden.id}"]))
    assert has_element?(view, ~s([data-test="season-row-#{shown.id}"]))

    view
    |> element(~s([data-test="season-visibility-#{hidden.id}"]))
    |> render_click()

    assert {:ok, %{visible: true}} = Content.get_season(org, hidden.id)
  end
end
