defmodule Marquee.Viewers do
  @moduledoc """
  Context for viewer identity and authentication.

  Viewers are customers of an organization — completely separate from
  the operator User/Membership system. This context is intentionally
  NOT under Accounts. Accounts manages operators; Viewers manages viewers.
  """

  import Ecto.Query, warn: false

  require Marquee.Otel
  require Logger

  alias Marquee.Accounts.Organization
  alias Marquee.Audit
  alias Marquee.Events
  alias Marquee.Pagination
  alias Marquee.PlatformBilling.UsageLimits
  alias Marquee.Repo
  alias Marquee.Viewers.{Viewer, ViewerNotifier, ViewerToken}

  ## -----------------------------------------------------------------------
  ## Registration
  ## -----------------------------------------------------------------------

  @doc """
  Registers a new viewer for an organization.

  Normalizes email to lowercase. Returns `{:ok, viewer}` on success,
  `{:error, :validation, changeset}` on validation failure. Enforces the
  organization's plan viewer cap: `{:error, :plan_limit_reached, status}` when
  the cap is reached, or `{:error, :trial_expired, %{trial_end:}}` when the
  org's trial has lapsed without payment.

  Exempt from doctest — hits the database.
  """
  def register_viewer(%Organization{} = organization, attrs) do
    case UsageLimits.check_register_viewer(organization) do
      :ok -> do_register_viewer(organization, attrs)
      {:error, _reason, _meta} = error -> error
    end
  end

  defp do_register_viewer(%Organization{} = organization, attrs) do
    Marquee.Otel.with_span "marquee.viewers.register",
                           %{"marquee.org.id" => organization.id} do
      changeset =
        Viewer.registration_changeset(
          %Viewer{organization_id: organization.id},
          attrs
        )

      case Repo.insert(changeset) do
        {:ok, viewer} ->
          Events.broadcast(%{organization: organization}, {:viewer_registered, viewer})
          viewer_registered_metric(organization.id)
          {:ok, viewer}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Returns a changeset for viewer registration form tracking.

  ## Examples

      iex> change_viewer_registration(%Marquee.Accounts.Organization{id: "123"})
      %Ecto.Changeset{data: %Marquee.Viewers.Viewer{}}
  """
  def change_viewer_registration(%Organization{id: org_id}, attrs \\ %{}) do
    Viewer.registration_changeset(%Viewer{organization_id: org_id}, attrs)
  end

  ## -----------------------------------------------------------------------
  ## Auth — lookup by email / session token
  ## -----------------------------------------------------------------------

  @doc """
  Gets a viewer by email within an organization.

  Returns nil if not found or if the viewer belongs to a different org.

  Exempt from doctest — hits the database.
  """
  def get_viewer_by_email(%Organization{id: org_id}, email) when is_binary(email) do
    email = String.downcase(email)

    Viewer
    |> where(organization_id: ^org_id, email: ^email)
    |> where([v], is_nil(v.deleted_at))
    |> Repo.one()
  end

  @doc """
  Gets a viewer by their session token.

  Exempt from doctest — hits the database.
  """
  def get_viewer_by_session_token(token) do
    {:ok, query} = ViewerToken.verify_session_token_query(token)
    viewer = Repo.one(query)
    if Marquee.SubscriberDemo.expired?(viewer), do: nil, else: viewer
  end

  @doc """
  Generates a session token for a viewer.

  Exempt from doctest — hits the database.
  """
  def generate_viewer_session_token(%Viewer{} = viewer) do
    {token, viewer_token} = ViewerToken.build_session_token(viewer)
    Repo.insert!(viewer_token)
    token
  end

  @doc """
  Deletes a viewer session token.

  Exempt from doctest — hits the database.
  """
  def delete_viewer_session_token(token) do
    Repo.delete_all(from(ViewerToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## -----------------------------------------------------------------------
  ## Magic link
  ## -----------------------------------------------------------------------

  @doc """
  Delivers a magic link email to a viewer if they exist and are active.

  Always returns `{:ok, :sent}` or `{:ok, :not_found}` to prevent
  email enumeration.

  Exempt from doctest — sends email.
  """
  def deliver_viewer_magic_link(%Organization{} = organization, email) do
    Marquee.Otel.with_span "marquee.viewers.deliver_magic_link",
                           %{"marquee.org.id" => organization.id} do
      case get_viewer_by_email(organization, email) do
        nil ->
          {:ok, :not_found}

        %Viewer{status: status} when status in [:banned, :suspended] ->
          {:ok, :not_found}

        %Viewer{} = viewer ->
          {token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
          Repo.insert!(viewer_token)
          ViewerNotifier.deliver_magic_link(viewer, token, organization)
          {:ok, :sent}
      end
    end
  end

  @doc """
  Verifies a magic link token and returns the viewer.

  Sets `confirmed_at` on first verification.

  Exempt from doctest — hits the database.
  """
  def verify_viewer_magic_link(token) do
    case ViewerToken.verify_magic_link_token_query(token) do
      {:ok, query} ->
        case Repo.one(query) do
          nil ->
            {:error, :invalid_token}

          %Viewer{} = viewer ->
            viewer = maybe_confirm_viewer(viewer)
            delete_used_magic_link_tokens(viewer)
            {:ok, viewer}
        end

      :error ->
        {:error, :invalid_token}
    end
  end

  defp maybe_confirm_viewer(%Viewer{confirmed_at: nil} = viewer) do
    {:ok, viewer} =
      viewer
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()

    viewer
  end

  defp maybe_confirm_viewer(viewer), do: viewer

  defp delete_used_magic_link_tokens(viewer) do
    Repo.delete_all(
      from(t in ViewerToken, where: t.viewer_id == ^viewer.id and t.context == "magic_link")
    )
  end

  ## -----------------------------------------------------------------------
  ## CRUD
  ## -----------------------------------------------------------------------

  @doc """
  Gets a viewer by ID within an organization.

  Returns `{:ok, viewer}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_viewer(%Organization{id: org_id}, id) do
    Viewer
    |> where(organization_id: ^org_id, id: ^id)
    |> where([v], is_nil(v.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      viewer -> {:ok, viewer}
    end
  end

  @doc """
  Gets a viewer by ID within an organization. Raises on not found.

  Exempt from doctest — hits the database.
  """
  def get_viewer!(%Organization{id: org_id}, id) do
    Viewer
    |> where(organization_id: ^org_id, id: ^id)
    |> where([v], is_nil(v.deleted_at))
    |> Repo.one!()
  end

  @doc """
  Gets a viewer by ID (without org scoping). Used for session token lookups
  and impersonation where the org is not yet known.

  Exempt from doctest — hits the database.
  """
  def get_viewer_by_id(id) do
    Repo.get(Viewer, id)
  end

  @doc """
  Updates a viewer's profile.

  Exempt from doctest — hits the database.
  """
  def update_viewer_profile(scope, %Viewer{} = viewer, attrs) do
    Marquee.Otel.with_span "marquee.viewers.update_profile",
                           %{"marquee.org.id" => viewer.organization_id} do
      case viewer |> Viewer.profile_changeset(attrs) |> Repo.update() do
        {:ok, viewer} ->
          Events.broadcast(scope, {:viewer_updated, viewer})
          Audit.log(scope, "viewer.profile_updated", viewer, attrs)
          {:ok, viewer}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Returns a paginated list of viewers for an organization.

  Supports `:search`, `:status`, and `:subscription_status` filters.

  Exempt from doctest — hits the database.
  """
  def list_viewers(%Organization{id: org_id}, opts \\ []) do
    Viewer
    |> where(organization_id: ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> apply_viewer_search(Keyword.get(opts, :search))
    |> apply_viewer_status_filter(Keyword.get(opts, :status))
    |> apply_viewer_subscription_filter(Keyword.get(opts, :subscription_status))
    |> order_by(desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  defp apply_viewer_search(query, nil), do: query

  defp apply_viewer_search(query, term) do
    pattern = "%#{term}%"
    where(query, [v], ilike(v.email, ^pattern) or ilike(v.display_name, ^pattern))
  end

  defp apply_viewer_status_filter(query, nil), do: query
  defp apply_viewer_status_filter(query, status), do: where(query, status: ^status)

  defp apply_viewer_subscription_filter(query, nil), do: query

  defp apply_viewer_subscription_filter(query, sub_status),
    do: where(query, subscription_status: ^sub_status)

  @doc """
  Returns the total number of viewers for an organization.

  Exempt from doctest — hits the database.
  """
  def count_viewers(%Organization{id: org_id}) do
    Viewer
    |> where(organization_id: ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns viewer counts grouped by status for an organization.

  Exempt from doctest — hits the database.
  """
  def count_viewers_by_status(%Organization{id: org_id}) do
    Viewer
    |> where(organization_id: ^org_id)
    |> where([v], is_nil(v.deleted_at))
    |> group_by(:status)
    |> select([v], {v.status, count(v.id)})
    |> Repo.all()
    |> Map.new()
  end

  ## -----------------------------------------------------------------------
  ## Account actions (operator-initiated)
  ## -----------------------------------------------------------------------

  @doc """
  Suspends a viewer account. Reversible via `reactivate_viewer/2`.

  Exempt from doctest — hits the database.
  """
  def suspend_viewer(scope, %Viewer{} = viewer) do
    change_viewer_status(scope, viewer, :suspended, "viewer.suspended")
  end

  @doc """
  Bans a viewer account. Reversible via `reactivate_viewer/2`.

  Exempt from doctest — hits the database.
  """
  def ban_viewer(scope, %Viewer{} = viewer) do
    change_viewer_status(scope, viewer, :banned, "viewer.banned")
  end

  @doc """
  Reactivates a suspended or banned viewer account.

  Exempt from doctest — hits the database.
  """
  def reactivate_viewer(scope, %Viewer{} = viewer) do
    change_viewer_status(scope, viewer, :active, "viewer.reactivated")
  end

  defp change_viewer_status(scope, viewer, status, action) do
    Marquee.Otel.with_span "marquee.viewers.#{action}",
                           %{"marquee.org.id" => viewer.organization_id} do
      case viewer |> Viewer.status_changeset(%{status: status}) |> Repo.update() do
        {:ok, viewer} ->
          Events.broadcast(scope, {String.to_atom(action), viewer})
          Audit.log(scope, action, viewer, %{status: status})
          {:ok, viewer}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Grants subscription access to a viewer with an optional expiry.

  Exempt from doctest — hits the database.
  """
  def grant_access(scope, %Viewer{} = viewer, expires_at \\ nil) do
    Marquee.Otel.with_span "marquee.viewers.grant_access",
                           %{"marquee.org.id" => viewer.organization_id} do
      attrs = %{subscription_status: "active", subscription_expires_at: expires_at}

      case viewer |> Viewer.subscription_changeset(attrs) |> Repo.update() do
        {:ok, viewer} ->
          Events.broadcast(scope, {:viewer_access_granted, viewer})
          Audit.log(scope, "viewer.access_granted", viewer, attrs)
          {:ok, viewer}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Revokes subscription access from a viewer.

  Exempt from doctest — hits the database.
  """
  def revoke_access(scope, %Viewer{} = viewer) do
    Marquee.Otel.with_span "marquee.viewers.revoke_access",
                           %{"marquee.org.id" => viewer.organization_id} do
      attrs = %{subscription_status: "none", subscription_expires_at: nil}

      case viewer |> Viewer.subscription_changeset(attrs) |> Repo.update() do
        {:ok, viewer} ->
          Events.broadcast(scope, {:viewer_access_revoked, viewer})
          Audit.log(scope, "viewer.access_revoked", viewer, attrs)
          {:ok, viewer}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Sets a viewer's subscription status directly.

  Exempt from doctest — hits the database.
  """
  def set_subscription_status(scope, %Viewer{} = viewer, status) do
    attrs = %{subscription_status: status}

    case viewer |> Viewer.subscription_changeset(attrs) |> Repo.update() do
      {:ok, viewer} ->
        Audit.log(scope, "viewer.subscription_status_set", viewer, attrs)
        {:ok, viewer}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  @doc """
  Sets a viewer's subscription status to trial with an expiration date.

  Exempt from doctest — hits the database.
  """
  def set_subscription_status_with_trial(scope, %Viewer{} = viewer, status, trial_expires_at) do
    attrs = %{subscription_status: status, trial_expires_at: trial_expires_at}

    case viewer |> Viewer.subscription_changeset(attrs) |> Repo.update() do
      {:ok, viewer} ->
        Audit.log(scope, "viewer.subscription_status_set", viewer, attrs)
        {:ok, viewer}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  ## -----------------------------------------------------------------------
  ## Deletion
  ## -----------------------------------------------------------------------

  @doc """
  Soft-deletes a viewer by setting `deleted_at`.

  Exempt from doctest — hits the database.
  """
  def delete_viewer(scope, %Viewer{} = viewer) do
    Marquee.Otel.with_span "marquee.viewers.delete",
                           %{"marquee.org.id" => viewer.organization_id} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      case viewer |> Ecto.Changeset.change(deleted_at: now) |> Repo.update() do
        {:ok, viewer} ->
          # Invalidate all session tokens
          Repo.delete_all(from(t in ViewerToken, where: t.viewer_id == ^viewer.id))
          Events.broadcast(scope, {:viewer_deleted, viewer})
          Audit.log(scope, "viewer.deleted", viewer)
          {:ok, viewer}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Hard-deletes all viewer data for GDPR erasure.

  Exempt from doctest — hits the database.
  """
  def hard_delete_viewer_data(%Organization{id: org_id}, %Viewer{} = viewer) do
    Marquee.Otel.with_span "marquee.viewers.hard_delete",
                           %{"marquee.org.id" => org_id} do
      if viewer.organization_id != org_id do
        {:error, :forbidden}
      else
        Repo.delete_all(from(t in ViewerToken, where: t.viewer_id == ^viewer.id))
        Repo.delete(viewer)
      end
    end
  end

  ## -----------------------------------------------------------------------
  ## Metrics
  ## -----------------------------------------------------------------------

  defp viewer_registered_metric(org_id) do
    :telemetry.execute(
      [:marquee, :viewer, :registered],
      %{count: 1},
      %{org_id: org_id}
    )
  end
end
