defmodule Bobine.WebhooksTest do
  use Bobine.DataCase

  alias Bobine.Webhooks

  describe "webhook_endpoints" do
    alias Bobine.Webhooks.Endpoint

    import Bobine.WebhooksFixtures

    @invalid_attrs %{active: nil, events: nil, url: nil, secret: nil}

    setup do
      %{org: insert(:organization)}
    end

    test "list_webhook_endpoints/0 returns all webhook_endpoints" do
      endpoint = endpoint_fixture()
      assert Webhooks.list_webhook_endpoints() == [endpoint]
    end

    test "get_endpoint!/1 returns the endpoint with given id" do
      endpoint = endpoint_fixture()
      assert Webhooks.get_endpoint!(endpoint.id) == endpoint
    end

    test "create_endpoint/1 with valid data creates a endpoint", %{org: org} do
      valid_attrs = %{
        active: true,
        events: ["option1", "option2"],
        url: "some url",
        secret: "some secret",
        organization_id: org.id
      }

      assert {:ok, %Endpoint{} = endpoint} = Webhooks.create_endpoint(valid_attrs)
      assert endpoint.active == true
      assert endpoint.events == ["option1", "option2"]
      assert endpoint.url == "some url"
      assert endpoint.secret == "some secret"
    end

    test "create_endpoint/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Webhooks.create_endpoint(@invalid_attrs)
    end

    test "update_endpoint/2 with valid data updates the endpoint" do
      endpoint = endpoint_fixture()

      update_attrs = %{
        active: false,
        events: ["option1"],
        url: "some updated url",
        secret: "some updated secret"
      }

      assert {:ok, %Endpoint{} = endpoint} = Webhooks.update_endpoint(endpoint, update_attrs)
      assert endpoint.active == false
      assert endpoint.events == ["option1"]
      assert endpoint.url == "some updated url"
      assert endpoint.secret == "some updated secret"
    end

    test "update_endpoint/2 with invalid data returns error changeset" do
      endpoint = endpoint_fixture()
      assert {:error, %Ecto.Changeset{}} = Webhooks.update_endpoint(endpoint, @invalid_attrs)
      assert endpoint == Webhooks.get_endpoint!(endpoint.id)
    end

    test "delete_endpoint/1 deletes the endpoint" do
      endpoint = endpoint_fixture()
      assert {:ok, %Endpoint{}} = Webhooks.delete_endpoint(endpoint)
      assert_raise Ecto.NoResultsError, fn -> Webhooks.get_endpoint!(endpoint.id) end
    end

    test "change_endpoint/1 returns a endpoint changeset" do
      endpoint = endpoint_fixture()
      assert %Ecto.Changeset{} = Webhooks.change_endpoint(endpoint)
    end
  end
end
