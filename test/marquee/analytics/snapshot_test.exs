defmodule Marquee.Analytics.SnapshotTest do
  use Marquee.DataCase, async: true

  alias Marquee.Analytics.Snapshot

  describe "changeset/2" do
    test "valid attrs produces valid changeset" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "daily_subscribers",
        value: Decimal.new("42")
      }

      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      assert changeset.valid?
    end

    test "metadata defaults to empty map" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "daily_views",
        value: Decimal.new("100")
      }

      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      assert changeset.valid?
    end

    test "requires organization_id" do
      attrs = %{period_date: ~D[2026-01-01], metric_type: "daily_views", value: Decimal.new("1")}
      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      assert "can't be blank" in errors_on(changeset).organization_id
    end

    test "requires period_date" do
      org = insert(:organization)

      attrs = %{organization_id: org.id, metric_type: "daily_views", value: Decimal.new("1")}
      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      assert "can't be blank" in errors_on(changeset).period_date
    end

    test "requires metric_type" do
      org = insert(:organization)

      attrs = %{organization_id: org.id, period_date: ~D[2026-01-01], value: Decimal.new("1")}
      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      assert "can't be blank" in errors_on(changeset).metric_type
    end

    test "requires value" do
      org = insert(:organization)

      attrs = %{organization_id: org.id, period_date: ~D[2026-01-01], metric_type: "daily_views"}
      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      assert "can't be blank" in errors_on(changeset).value
    end

    test "rejects unknown metric_type" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "invalid_metric",
        value: Decimal.new("1")
      }

      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).metric_type
    end

    test "enforces unique constraint on org + date + metric" do
      org = insert(:organization)

      insert(:analytics_snapshot,
        organization: org,
        period_date: ~D[2026-01-01],
        metric_type: "daily_views"
      )

      attrs = %{
        organization_id: org.id,
        period_date: ~D[2026-01-01],
        metric_type: "daily_views",
        value: Decimal.new("99")
      }

      {:error, changeset} = Repo.insert(Snapshot.changeset(%Snapshot{}, attrs))
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :organization_id) or Map.has_key?(errors, :metric_type)
    end
  end
end
