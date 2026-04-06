defmodule Bobine.Content.SeasonTest do
  use Bobine.DataCase

  alias Bobine.Content.Season

  describe "changeset/2" do
    test "with valid attrs succeeds" do
      changeset = Season.changeset(%Season{}, %{title: "Season One", season_number: 1})
      assert changeset.valid?
    end

    test "without title fails" do
      changeset = Season.changeset(%Season{}, %{season_number: 1})
      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "without season_number fails" do
      changeset = Season.changeset(%Season{}, %{title: "Season One"})
      refute changeset.valid?
      assert %{season_number: ["can't be blank"]} = errors_on(changeset)
    end

    test "season_number must be > 0" do
      changeset = Season.changeset(%Season{}, %{title: "Season Zero", season_number: 0})
      refute changeset.valid?
      assert %{season_number: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "season_number unique within series" do
      series = insert(:series)
      insert(:season, series: series, organization: series.organization, season_number: 1)

      {:error, changeset} =
        %Season{organization_id: series.organization.id, series_id: series.id}
        |> Season.changeset(%{title: "Duplicate", season_number: 1})
        |> Repo.insert()

      assert %{series_id: _} = errors_on(changeset)
    end

    test "same season_number in different series is allowed" do
      org = insert(:organization)
      series_a = insert(:series, organization: org)
      series_b = insert(:series, organization: org)
      insert(:season, series: series_a, organization: org, season_number: 1)

      assert {:ok, _} =
               %Season{organization_id: org.id, series_id: series_b.id}
               |> Season.changeset(%{title: "Series B Season 1", season_number: 1})
               |> Repo.insert()
    end
  end
end
