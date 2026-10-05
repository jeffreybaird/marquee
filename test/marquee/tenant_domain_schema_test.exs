defmodule Marquee.TenantDomains.DomainTest do
  use Marquee.DataCase, async: true

  alias Marquee.TenantDomains.Domain

  test "persisted allocation requires explicit eligibility source and timestamp" do
    org = insert(:organization)
    assert {:ok, domain} = org |> changeset(attrs()) |> Repo.insert()
    assert domain.eligibility_source == :backend
    assert domain.eligible_at != nil

    for field <- [:eligibility_source, :eligible_at] do
      changeset = changeset(insert(:organization), Map.delete(attrs(), field))
      assert {:error, invalid} = Repo.insert(changeset)
      assert "can't be blank" in errors_on(invalid)[field]
    end
  end

  test "organization and hostname allocations are unique across concurrent enrollment paths" do
    org = insert(:organization)
    allocation = attrs()
    assert {:ok, _} = org |> changeset(allocation) |> Repo.insert()

    assert {:error, duplicate_org} =
             org
             |> changeset(%{allocation | hostname: "different-marquee.jeffreybaird.com"})
             |> Repo.insert()

    assert "has already been taken" in errors_on(duplicate_org).organization_id

    assert {:error, duplicate_host} =
             insert(:organization) |> changeset(allocation) |> Repo.insert()

    assert "has already been taken" in errors_on(duplicate_host).hostname
  end

  defp changeset(org, attrs), do: Domain.changeset(%Domain{organization_id: org.id}, attrs)

  defp attrs do
    %{
      hostname: "studio-#{System.unique_integer([:positive])}-marquee.jeffreybaird.com",
      host_pattern: "{slug}-marquee.jeffreybaird.com",
      dns_zone: "jeffreybaird.com",
      target_ipv4: "192.0.2.25",
      generation: Ecto.UUID.generate(),
      eligibility_source: :backend,
      eligible_at: DateTime.utc_now()
    }
  end
end
