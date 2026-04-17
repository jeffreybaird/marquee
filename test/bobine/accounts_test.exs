defmodule Bobine.AccountsTest do
  use Bobine.DataCase

  alias Bobine.Accounts

  doctest Bobine.Accounts,
    only: [
      registration_changeset: 1,
      merge_registration_errors: 2,
      role_at_least?: 2,
      can_manage_content?: 1,
      can_manage_viewers?: 1,
      can_view_viewers?: 1
    ]

  import Bobine.AccountsFixtures
  alias Bobine.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, :validation, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, :validation, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, :validation, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, :validation, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, :validation, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "register_user_with_organization/3" do
    alias Bobine.Branding
    alias Bobine.Branding.Theme

    test "creates the org's starter theme from the chosen preset" do
      email = unique_user_email()

      {:ok, _user, org} =
        Accounts.register_user_with_organization(%{email: email}, "Daybreak Studio", "daybreak")

      theme = Branding.get_theme_by_org(org)
      preset = Theme.preset_attrs("daybreak")

      assert theme.background == preset.background
      assert theme.brand_primary == preset.brand_primary
      assert theme.text_primary == preset.text_primary
      assert theme.form_text == preset.form_text
    end

    test "supports each available preset" do
      for key <- Theme.preset_keys() do
        email = unique_user_email()

        {:ok, _user, org} =
          Accounts.register_user_with_organization(
            %{email: email},
            "Org #{key} #{System.unique_integer([:positive])}",
            key
          )

        theme = Branding.get_theme_by_org(org)
        preset = Theme.preset_attrs(key)

        assert theme.background == preset.background, "background mismatch for preset #{key}"

        assert theme.brand_primary == preset.brand_primary,
               "brand_primary mismatch for preset #{key}"
      end
    end

    test "falls back to the default preset when none is supplied" do
      email = unique_user_email()

      {:ok, _user, org} =
        Accounts.register_user_with_organization(%{email: email}, "Default Theme Org")

      theme = Branding.get_theme_by_org(org)
      default = Theme.preset_attrs(Theme.default_preset_key())

      assert theme.background == default.background
      assert theme.brand_primary == default.brand_primary
    end

    test "falls back to the default preset when an unknown key is supplied" do
      email = unique_user_email()

      {:ok, _user, org} =
        Accounts.register_user_with_organization(
          %{email: email},
          "Unknown Theme Org",
          "neon-rainbow"
        )

      theme = Branding.get_theme_by_org(org)
      default = Theme.preset_attrs(Theme.default_preset_key())

      assert theme.background == default.background
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, :validation, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, :validation, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      import Ecto.Query
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(where(User, id: ^user.id), set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  # ---------------------------------------------------------------------------
  # Organization getters
  # ---------------------------------------------------------------------------

  describe "get_organization_by_slug/1" do
    test "returns {:ok, org} when slug matches" do
      org = insert(:organization)
      assert {:ok, found} = Accounts.get_organization_by_slug(org.slug)
      assert found.id == org.id
    end

    test "returns {:error, :not_found} when slug does not match" do
      assert {:error, :not_found} = Accounts.get_organization_by_slug("nonexistent-slug")
    end

    test "does not return an org from a different slug" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      assert {:ok, found} = Accounts.get_organization_by_slug(org_a.slug)
      refute found.id == org_b.id
    end
  end

  describe "get_organization_by_custom_domain/1" do
    test "returns {:ok, org} when custom_domain matches" do
      org = insert(:organization, custom_domain: "myapp-#{System.unique_integer()}.com")
      assert {:ok, found} = Accounts.get_organization_by_custom_domain(org.custom_domain)
      assert found.id == org.id
    end

    test "returns {:error, :not_found} when domain does not match" do
      assert {:error, :not_found} =
               Accounts.get_organization_by_custom_domain("nope.example.com")
    end

    test "returns {:error, :not_found} when domain is nil" do
      assert {:error, :not_found} = Accounts.get_organization_by_custom_domain(nil)
    end
  end

  describe "get_organization/1" do
    test "returns {:ok, org} when id matches" do
      org = insert(:organization)
      assert {:ok, found} = Accounts.get_organization(org.id)
      assert found.id == org.id
    end

    test "returns {:error, :not_found} when id does not match" do
      assert {:error, :not_found} =
               Accounts.get_organization("00000000-0000-0000-0000-000000000000")
    end

    test "returns {:error, :not_found} for nil id" do
      assert {:error, :not_found} = Accounts.get_organization(nil)
    end

    test "returns {:error, :not_found} for non-binary id" do
      assert {:error, :not_found} = Accounts.get_organization(123)
    end
  end

  describe "fetch_any_organization/0" do
    test "returns {:error, :not_found} when no organizations exist" do
      assert {:error, :not_found} = Accounts.fetch_any_organization()
    end

    test "returns {:ok, org} when at least one organization exists" do
      org = insert(:organization)
      assert {:ok, found} = Accounts.fetch_any_organization()
      assert found.id == org.id
    end

    test "returns the oldest organization" do
      oldest = insert(:organization)
      _newer = insert(:organization)
      assert {:ok, found} = Accounts.fetch_any_organization()
      assert found.id == oldest.id
    end
  end

  describe "fetch_user_primary_organization/1" do
    test "returns {:ok, org} when user has a non-deleted membership" do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user)

      assert {:ok, found} = Accounts.fetch_user_primary_organization(user)
      assert found.id == org.id
    end

    test "returns {:error, :not_found} when user has no memberships" do
      user = insert(:user)
      assert {:error, :not_found} = Accounts.fetch_user_primary_organization(user)
    end

    test "skips soft-deleted organizations" do
      org = insert(:organization, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      user = insert(:user)
      insert(:membership, organization: org, user: user)

      assert {:error, :not_found} = Accounts.fetch_user_primary_organization(user)
    end
  end

  describe "get_membership/2" do
    test "returns the membership when user is a member of the org" do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      found = Accounts.get_membership(org, user)
      assert found.id == membership.id
    end

    test "returns nil when user is not a member of the org" do
      org = insert(:organization)
      user = insert(:user)

      assert is_nil(Accounts.get_membership(org, user))
    end

    test "does not return membership from a different org" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org_a, user: user)

      assert is_nil(Accounts.get_membership(org_b, user))
    end
  end

  # ---------------------------------------------------------------------------
  # RBAC helpers
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Permission helpers (pure functions — no DB needed)
  # ---------------------------------------------------------------------------

  describe "can_manage_content?/1" do
    test "super admins can always manage content" do
      scope = %{user: %{is_super_admin: true}, membership: nil}
      assert Accounts.can_manage_content?(scope)
    end

    test "owner role can manage content" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :owner}
      }

      assert Accounts.can_manage_content?(scope)
    end

    test "admin role can manage content" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :admin}
      }

      assert Accounts.can_manage_content?(scope)
    end

    test "editor role can manage content" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :editor}
      }

      assert Accounts.can_manage_content?(scope)
    end

    test "viewer_support role cannot manage content" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :viewer_support}
      }

      refute Accounts.can_manage_content?(scope)
    end

    test "nil membership cannot manage content" do
      scope = %{user: %{is_super_admin: false}, membership: nil}
      refute Accounts.can_manage_content?(scope)
    end
  end

  describe "can_manage_viewers?/1" do
    test "super admins can always manage viewers" do
      scope = %{user: %{is_super_admin: true}, membership: nil}
      assert Accounts.can_manage_viewers?(scope)
    end

    test "owner role can manage viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :owner}
      }

      assert Accounts.can_manage_viewers?(scope)
    end

    test "admin role can manage viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :admin}
      }

      assert Accounts.can_manage_viewers?(scope)
    end

    test "viewer_support role can manage viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :viewer_support}
      }

      assert Accounts.can_manage_viewers?(scope)
    end

    test "editor role cannot manage viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :editor}
      }

      refute Accounts.can_manage_viewers?(scope)
    end

    test "nil membership cannot manage viewers" do
      scope = %{user: %{is_super_admin: false}, membership: nil}
      refute Accounts.can_manage_viewers?(scope)
    end
  end

  describe "can_view_viewers?/1" do
    test "super admins can always view viewers" do
      scope = %{user: %{is_super_admin: true}, membership: nil}
      assert Accounts.can_view_viewers?(scope)
    end

    test "owner role can view viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :owner}
      }

      assert Accounts.can_view_viewers?(scope)
    end

    test "admin role can view viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :admin}
      }

      assert Accounts.can_view_viewers?(scope)
    end

    test "editor role can view viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :editor}
      }

      assert Accounts.can_view_viewers?(scope)
    end

    test "viewer_support role can view viewers" do
      scope = %{
        user: %{is_super_admin: false},
        membership: %Bobine.Accounts.Membership{role: :viewer_support}
      }

      assert Accounts.can_view_viewers?(scope)
    end

    test "nil membership cannot view viewers" do
      scope = %{user: %{is_super_admin: false}, membership: nil}
      refute Accounts.can_view_viewers?(scope)
    end
  end

  describe "role_at_least?/2" do
    test "owner meets owner minimum" do
      assert Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :owner}, :owner)
    end

    test "owner meets admin minimum" do
      assert Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :owner}, :admin)
    end

    test "owner meets editor minimum" do
      assert Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :owner}, :editor)
    end

    test "owner meets viewer_support minimum" do
      assert Accounts.role_at_least?(
               %Bobine.Accounts.Membership{role: :owner},
               :viewer_support
             )
    end

    test "admin meets admin minimum" do
      assert Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :admin}, :admin)
    end

    test "admin meets editor minimum" do
      assert Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :admin}, :editor)
    end

    test "admin does not meet owner minimum" do
      refute Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :admin}, :owner)
    end

    test "editor meets editor minimum" do
      assert Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :editor}, :editor)
    end

    test "editor does not meet admin minimum" do
      refute Accounts.role_at_least?(%Bobine.Accounts.Membership{role: :editor}, :admin)
    end

    test "viewer_support meets viewer_support minimum" do
      assert Accounts.role_at_least?(
               %Bobine.Accounts.Membership{role: :viewer_support},
               :viewer_support
             )
    end

    test "viewer_support does not meet editor minimum" do
      refute Accounts.role_at_least?(
               %Bobine.Accounts.Membership{role: :viewer_support},
               :editor
             )
    end
  end
end
