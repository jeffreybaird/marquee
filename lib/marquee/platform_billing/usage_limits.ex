defmodule Marquee.PlatformBilling.UsageLimits do
  @moduledoc """
  Checks whether an organization can perform actions given their platform
  plan limits. Used by context functions to enforce plan-based restrictions.
  """

  alias Marquee.Accounts.Organization
  alias Marquee.Admin
  alias Marquee.Content
  alias Marquee.PlatformBilling
  alias Marquee.Viewers

  @doc """
  Returns true if the organization can upload another video.

  Exempt from doctest — hits the database.
  """
  def can_upload_video?(%Organization{} = organization) do
    plan = get_plan_for_org(organization)

    case plan.max_videos do
      nil -> true
      limit -> Admin.video_count(organization) < limit
    end
  end

  @doc """
  Returns true if the organization can add another team member.

  Exempt from doctest — hits the database.
  """
  def can_add_team_member?(%Organization{} = organization) do
    plan = get_plan_for_org(organization)

    case plan.max_team_seats do
      nil -> true
      limit -> Admin.member_count(organization) < limit
    end
  end

  @doc """
  Returns true if the organization can add another webhook endpoint.

  Exempt from doctest — hits the database.
  """
  def can_add_webhook_endpoint?(%Organization{} = organization) do
    plan = get_plan_for_org(organization)

    case plan.max_webhook_endpoints do
      nil -> true
      limit -> count_webhook_endpoints(organization) < limit
    end
  end

  @doc """
  Returns a status map with the current video count vs the plan limit.

  Exempt from doctest — hits the database.
  """
  def video_limit_status(%Organization{} = organization) do
    plan = get_plan_for_org(organization)
    current = Admin.video_count(organization)

    %{
      current: current,
      limit: plan.max_videos,
      reached: plan.max_videos != nil and current >= plan.max_videos
    }
  end

  @doc """
  Returns the plan for the organization, falling back to the default free plan.

  Exempt from doctest — hits the database.
  """
  def get_plan_for_org(%Organization{} = organization) do
    case PlatformBilling.get_subscription(organization) do
      {:ok, %{platform_plan_id: nil}} -> PlatformBilling.trial_plan()
      {:ok, sub} -> PlatformBilling.get_platform_plan!(sub.platform_plan_id)
      _ -> PlatformBilling.default_free_plan()
    end
  end

  @doc """
  Composes the full pre-upload gate: soft-lock, video-count limit, then
  total-duration limit. Returns `:ok` or a tagged error tuple.

  Exempt from doctest — hits the database.
  """
  def check_upload(%Organization{} = organization) do
    cond do
      PlatformBilling.soft_locked?(organization) ->
        {:error, :trial_expired, trial_meta(organization)}

      not can_upload_video?(organization) ->
        {:error, :plan_limit_reached, video_limit_status(organization)}

      duration_limit_reached?(organization) ->
        {:error, :plan_limit_reached, duration_limit_status(organization)}

      true ->
        :ok
    end
  end

  @doc """
  Returns true if the org is under its total-video-duration cap.

  Exempt from doctest — hits the database.
  """
  def can_add_video_duration?(%Organization{} = organization) do
    not duration_limit_reached?(organization)
  end

  @doc """
  Returns a status map with the current total duration (seconds) vs the limit.

  Exempt from doctest — hits the database.
  """
  def duration_limit_status(%Organization{} = organization) do
    limit = get_plan_for_org(organization).max_total_duration_seconds
    current = Content.total_ready_duration(organization)

    %{
      current: current,
      limit: limit,
      unit: :seconds,
      reached: not unlimited?(limit) and current >= limit
    }
  end

  @doc """
  Composes the viewer-registration gate: soft-lock, then viewer-count limit.
  Returns `:ok` or a tagged error tuple.

  Exempt from doctest — hits the database.
  """
  def check_register_viewer(%Organization{} = organization) do
    cond do
      PlatformBilling.soft_locked?(organization) ->
        {:error, :trial_expired, trial_meta(organization)}

      not can_register_viewer?(organization) ->
        {:error, :plan_limit_reached, viewer_limit_status(organization)}

      true ->
        :ok
    end
  end

  @doc """
  Returns true if the org can register another viewer under its plan limit.

  Exempt from doctest — hits the database.
  """
  def can_register_viewer?(%Organization{} = organization) do
    limit = get_plan_for_org(organization).max_viewers

    unlimited?(limit) or Viewers.count_viewers(organization) < limit
  end

  @doc """
  Returns a status map with the current viewer count vs the plan limit.

  Exempt from doctest — hits the database.
  """
  def viewer_limit_status(%Organization{} = organization) do
    limit = get_plan_for_org(organization).max_viewers
    current = Viewers.count_viewers(organization)

    %{
      current: current,
      limit: limit,
      reached: not unlimited?(limit) and current >= limit
    }
  end

  @doc """
  Composes the custom-domain gate: soft-lock, then the plan's
  `allow_custom_domain` flag. Returns `:ok` or a tagged error tuple.

  Exempt from doctest — hits the database.
  """
  def check_custom_domain(%Organization{} = organization) do
    cond do
      PlatformBilling.soft_locked?(organization) ->
        {:error, :trial_expired, trial_meta(organization)}

      not can_use_custom_domain?(organization) ->
        {:error, :plan_limit_reached, %{feature: :custom_domain}}

      true ->
        :ok
    end
  end

  @doc """
  Returns true if the org's plan permits a custom domain.

  Exempt from doctest — hits the database.
  """
  def can_use_custom_domain?(%Organization{} = organization) do
    get_plan_for_org(organization).allow_custom_domain == true
  end

  # nil or any non-positive value (the -1 sentinel) means unlimited.
  defp unlimited?(nil), do: true
  defp unlimited?(limit) when is_number(limit) and limit <= 0, do: true
  defp unlimited?(_), do: false

  defp duration_limit_reached?(%Organization{} = organization) do
    limit = get_plan_for_org(organization).max_total_duration_seconds

    not unlimited?(limit) and Content.total_ready_duration(organization) >= limit
  end

  defp trial_meta(%Organization{} = organization) do
    case PlatformBilling.get_subscription(organization) do
      {:ok, sub} -> %{trial_end: sub.trial_end}
      _ -> %{trial_end: nil}
    end
  end

  defp count_webhook_endpoints(%Organization{id: org_id}) do
    import Ecto.Query
    alias Marquee.Webhooks.Endpoint

    Endpoint
    |> where(organization_id: ^org_id)
    |> where([e], is_nil(e.deleted_at))
    |> Marquee.Repo.aggregate(:count)
  end
end
