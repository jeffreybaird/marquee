defmodule Marquee.Content.SeriesTest do
  use Marquee.DataCase

  alias Marquee.Content.Series

  describe "changeset/2" do
    test "with valid attrs succeeds" do
      changeset = Series.changeset(%Series{}, %{title: "My Series"})
      assert changeset.valid?
    end

    test "without title fails" do
      changeset = Series.changeset(%Series{}, %{})
      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "slug auto-generated from title" do
      changeset = Series.changeset(%Series{}, %{title: "My Awesome Series!"})
      assert Ecto.Changeset.get_change(changeset, :slug) == "my-awesome-series"
    end

    test "slug unique per organization" do
      org = insert(:organization)
      insert(:series, organization: org, slug: "same-slug")

      {:error, changeset} =
        %Series{organization_id: org.id}
        |> Series.changeset(%{title: "Same Slug"})
        |> Ecto.Changeset.put_change(:slug, "same-slug")
        |> Repo.insert()

      assert %{organization_id: _} = errors_on(changeset)
    end

    test "same slug in different orgs is allowed" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      insert(:series, organization: org_a, slug: "shared-slug")

      assert {:ok, _} =
               %Series{organization_id: org_b.id}
               |> Series.changeset(%{title: "Shared Slug"})
               |> Ecto.Changeset.put_change(:slug, "shared-slug")
               |> Repo.insert()
    end
  end
end
