defmodule Bobine.WebhooksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Webhooks` context.
  """

  import Bobine.Factory

  @doc """
  Generate a endpoint.
  """
  def endpoint_fixture(attrs \\ %{}) do
    org = insert(:organization)

    {:ok, endpoint} =
      attrs
      |> Enum.into(%{
        organization_id: org.id,
        active: true,
        events: ["option1", "option2"],
        secret: "some secret",
        url: "some url"
      })
      |> Bobine.Webhooks.create_endpoint()

    endpoint
  end
end
