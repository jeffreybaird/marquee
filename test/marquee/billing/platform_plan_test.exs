defmodule Marquee.Billing.PlatformPlanTest do
  use Marquee.DataCase, async: true

  alias Marquee.Billing.PlatformPlan

  describe "changeset/2" do
    test "valid changeset with required attrs" do
      attrs = %{
        name: "Individual Basic",
        slug: "individual_basic",
        amount: 2900,
        usage_tier: :basic,
        business_tier: :individual
      }

      changeset = PlatformPlan.changeset(%PlatformPlan{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = PlatformPlan.changeset(%PlatformPlan{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:slug]
      assert errors[:amount]
      assert errors[:usage_tier]
      assert errors[:business_tier]
    end

    test "enforces unique constraint on slug" do
      insert(:platform_plan, slug: "unique_slug")

      {:error, changeset} =
        %PlatformPlan{}
        |> PlatformPlan.changeset(%{
          name: "Dup",
          slug: "unique_slug",
          amount: 100,
          usage_tier: :super,
          business_tier: :small_business
        })
        |> Repo.insert()

      assert errors_on(changeset)[:slug]
    end

    test "enforces unique constraint on [usage_tier, business_tier]" do
      insert(:platform_plan,
        slug: "first",
        usage_tier: :premium,
        business_tier: :enterprise
      )

      {:error, changeset} =
        %PlatformPlan{}
        |> PlatformPlan.changeset(%{
          name: "Second",
          slug: "second",
          amount: 100,
          usage_tier: :premium,
          business_tier: :enterprise
        })
        |> Repo.insert()

      assert errors_on(changeset)[:usage_tier]
    end
  end
end
