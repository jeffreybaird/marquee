defmodule Marquee.Onboarding.StarterContentTest do
  use Marquee.DataCase

  import Ecto.Query

  alias Marquee.Catalog.Row
  alias Marquee.Content
  alias Marquee.Content.{Collection, Video}
  alias Marquee.Onboarding.StarterContent
  alias Marquee.Repo

  defp sample_count(schema, org) do
    Repo.aggregate(
      from(r in schema,
        where: r.organization_id == ^org.id and r.is_sample and is_nil(r.deleted_at)
      ),
      :count
    )
  end

  describe "seed/1" do
    setup do
      %{org: insert(:organization)}
    end

    test "creates sample videos, collections, and rows, all flagged is_sample", %{org: org} do
      assert {:ok, summary} = StarterContent.seed(org)

      assert summary.videos == 10
      assert summary.collections == 3
      assert summary.rows == 6

      assert sample_count(Video, org) == 10
      assert sample_count(Collection, org) == 3
      # 6 rows: hero + curated + 2 collection + recent = 5 rows, plus hero is a row.
      assert sample_count(Row, org) == 5
    end

    test "seeded videos do not count against the trial duration cap", %{org: org} do
      assert {:ok, _} = StarterContent.seed(org)

      assert Content.total_ready_duration(org) == 0.0
    end

    test "is idempotent — a second seed adds nothing", %{org: org} do
      assert {:ok, _} = StarterContent.seed(org)
      before = sample_count(Video, org)

      assert {:ok, :already_seeded} = StarterContent.seed(org)
      assert sample_count(Video, org) == before
    end

    test "is scoped to the target organization", %{org: org} do
      other = insert(:organization)

      assert {:ok, _} = StarterContent.seed(org)

      assert sample_count(Video, other) == 0
      refute StarterContent.seeded?(other)
      assert StarterContent.seeded?(org)
    end

    test "accepts a scope as well as an organization" do
      org = insert(:organization)
      scope = %Marquee.Accounts.Scope{organization: org}

      assert {:ok, summary} = StarterContent.seed(scope)
      assert summary.videos == 10
    end
  end

  describe "clear/1" do
    setup do
      %{org: insert(:organization)}
    end

    test "soft-deletes only sample content, leaving operator content intact", %{org: org} do
      {:ok, _} = StarterContent.seed(org)
      operator_video = insert(:video, organization: org, is_sample: false)

      assert {:ok, counts} = StarterContent.clear(org)

      assert counts.videos == 10
      assert counts.collections == 3
      assert counts.rows == 5

      assert sample_count(Video, org) == 0
      # The operator's own video survives.
      assert Repo.get(Video, operator_video.id).deleted_at == nil
    end

    test "removing sample content re-opens seeding", %{org: org} do
      {:ok, _} = StarterContent.seed(org)
      {:ok, _} = StarterContent.clear(org)

      refute StarterContent.seeded?(org)
    end
  end
end
