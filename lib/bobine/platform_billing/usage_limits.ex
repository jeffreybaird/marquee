defmodule Bobine.PlatformBilling.UsageLimits do
  @moduledoc """
  Checks whether an organization can perform actions given their platform
  plan limits. Used by context functions to enforce plan-based restrictions.
  """

  alias Bobine.Accounts.Organization
  alias Bobine.Admin
  alias Bobine.PlatformBilling

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
      {:ok, sub} -> PlatformBilling.get_platform_plan!(sub.platform_plan_id)
      _ -> PlatformBilling.default_free_plan()
    end
  end

  defp count_webhook_endpoints(%Organization{id: org_id}) do
    import Ecto.Query
    alias Bobine.Webhooks.Endpoint

    Endpoint
    |> where(organization_id: ^org_id)
    |> where([e], is_nil(e.deleted_at))
    |> Bobine.Repo.aggregate(:count)
  end
end
