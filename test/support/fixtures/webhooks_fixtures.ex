defmodule Marquee.WebhooksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Marquee.Webhooks` context.
  """

  import Marquee.Factory

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
      |> Marquee.Webhooks.create_endpoint()

    endpoint
  end
end
