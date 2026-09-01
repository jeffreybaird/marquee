defmodule MarqueeWeb.Admin.OnboardingLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts
  alias Marquee.Branding

  doctest MarqueeWeb.Admin.OnboardingLive, only: [pending?: 2]

  defp owner_of_new_org do
    insert(:membership,
      role: :owner,
      organization: insert(:organization, onboarding_completed_at: nil)
    )
  end

  describe "gate" do
    test "a not-yet-onboarded owner landing on /admin is sent to the wizard" do
      membership = owner_of_new_org()

      assert {:error, {:live_redirect, %{to: "/admin/onboarding"}}} =
               live(conn_for(membership), ~p"/admin")
    end

    test "an already-onboarded owner reaches the dashboard, not the wizard" do
      org = insert(:organization)
      {:ok, _} = Accounts.complete_onboarding(org)
      membership = insert(:membership, role: :owner, organization: org)

      assert {:ok, _view, html} = live(conn_for(membership), ~p"/admin")
      assert html =~ "Dashboard"
    end

    test "an already-onboarded org visiting the wizard is bounced to the dashboard" do
      org = insert(:organization)
      {:ok, _} = Accounts.complete_onboarding(org)
      membership = insert(:membership, role: :owner, organization: org)

      assert {:error, {:live_redirect, %{to: "/admin"}}} =
               live(conn_for(membership), ~p"/admin/onboarding")
    end

    test "a non-owner/admin member is never shown the wizard" do
      membership =
        insert(:membership,
          role: :editor,
          organization: insert(:organization, onboarding_completed_at: nil)
        )

      assert {:error, {:live_redirect, %{to: "/admin"}}} =
               live(conn_for(membership), ~p"/admin/onboarding")
    end
  end

  describe "wizard flow" do
    test "renders the welcome step with a four-step progress bar" do
      {:ok, _view, html} = live(conn_for(owner_of_new_org()), ~p"/admin/onboarding")

      assert html =~ ~s(data-test="onboarding-step-1")
      assert html =~ "Welcome to"
      assert html =~ ~s(data-test="onboarding-progress")
    end

    test "advances from welcome to the theme step" do
      {:ok, view, _html} = live(conn_for(owner_of_new_org()), ~p"/admin/onboarding")

      html = view |> element(~s([data-test="onboarding-next"])) |> render_click()

      assert html =~ ~s(data-test="onboarding-step-2")
      assert html =~ "Choose a look"
      assert html =~ ~s(data-test="onboarding-theme-daybreak")
    end

    test "selecting a theme applies the preset to the org" do
      membership = owner_of_new_org()
      org = membership.organization
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/onboarding")

      view |> element(~s([data-test="onboarding-next"])) |> render_click()

      view
      |> element(~s([data-test="onboarding-theme-daybreak"] input))
      |> render_click()

      theme = Branding.get_theme_by_org(org)
      assert theme.background == Branding.Theme.preset_attrs("daybreak").background
    end

    test "finishing completes onboarding and redirects to the dashboard" do
      membership = owner_of_new_org()
      org = membership.organization
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/onboarding")

      # welcome -> theme -> video -> done
      for _ <- 1..3, do: view |> element(~s([data-test="onboarding-next"])) |> render_click()

      view |> element(~s([data-test="onboarding-finish"])) |> render_click()

      assert_redirect(view, ~p"/admin")
      assert Accounts.onboarding_complete?(Marquee.Repo.reload(org))
    end

    test "skipping also completes onboarding so the wizard won't reappear" do
      membership = owner_of_new_org()
      org = membership.organization
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/onboarding")

      view |> element(~s([data-test="onboarding-skip"])) |> render_click()

      assert_redirect(view, ~p"/admin")
      assert Accounts.onboarding_complete?(Marquee.Repo.reload(org))
    end
  end
end
