defmodule MarqueeWeb.UserLive.RegistrationTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marquee.AccountsFixtures

  alias Marquee.Branding.Theme

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
      assert html =~ "Organization name"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "organization_name" => ""})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account and organization", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form",
          user: %{"email" => email, "organization_name" => "My Studio"}
        )

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/

      # Verify org and membership were created
      user = Marquee.Accounts.get_user_by_email(email)
      assert user
      assert Marquee.Accounts.has_any_membership?(user)

      org = Marquee.Repo.get_by(Marquee.Accounts.Organization, slug: "my-studio")
      assert org
      assert org.name == "My Studio"

      membership = Marquee.Accounts.get_membership(org, user)
      assert membership.role == :owner
    end

    test "renders both starter theme presets", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Choose a starter theme"
      assert html =~ "Midnight"
      assert html =~ "Daybreak"
      assert html =~ ~s(data-test="registration-theme-preset-midnight")
      assert html =~ ~s(data-test="registration-theme-preset-daybreak")
    end

    test "applies the selected theme preset to the new organization", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form",
          user: %{
            "email" => email,
            "organization_name" => "Bright Studio",
            "theme_preset" => "daybreak"
          }
        )

      {:ok, _lv, _html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      org = Marquee.Repo.get_by(Marquee.Accounts.Organization, slug: "bright-studio")
      theme = Marquee.Branding.get_theme_by_org(org)
      preset = Theme.preset_attrs("daybreak")

      assert theme.background == preset.background
      assert theme.brand_primary == preset.brand_primary
    end

    test "rejects an unknown theme preset value via the form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          user: %{
            "email" => unique_user_email(),
            "organization_name" => "Bad Theme",
            "theme_preset" => "neon-rainbow"
          }
        )

      assert result =~ "is invalid"
    end

    test "requires organization name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      result =
        lv
        |> form("#registration_form", user: %{"email" => email, "organization_name" => ""})
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "organization_name" => "Test Org"}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end
