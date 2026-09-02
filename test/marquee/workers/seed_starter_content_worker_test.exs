defmodule Marquee.Workers.SeedStarterContentWorkerTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Onboarding.StarterContent
  alias Marquee.Workers.SeedStarterContentWorker

  describe "perform/1" do
    test "seeds starter content for the organization" do
      org = insert(:organization)

      assert :ok = perform_job(SeedStarterContentWorker, %{"organization_id" => org.id})
      assert StarterContent.seeded?(org)
    end

    test "is a no-op for an already-seeded org" do
      org = insert(:organization)
      {:ok, _} = StarterContent.seed(org)

      assert :ok = perform_job(SeedStarterContentWorker, %{"organization_id" => org.id})
    end

    test "is a no-op when the org no longer exists" do
      assert :ok =
               perform_job(SeedStarterContentWorker, %{
                 "organization_id" => Ecto.UUID.generate()
               })
    end
  end

  describe "enqueue on signup" do
    test "registering an organization seeds it (jobs run inline in test)" do
      {:ok, _user, org} =
        Marquee.Accounts.register_user_with_organization(
          %{email: "founder@example.com"},
          "Founder Studio"
        )

      assert StarterContent.seeded?(org)
    end
  end
end
