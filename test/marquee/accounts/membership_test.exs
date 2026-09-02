defmodule Marquee.Accounts.MembershipTest do
  use ExUnit.Case, async: true

  doctest Marquee.Accounts.Membership

  alias Marquee.Accounts.Membership

  describe "changeset/2" do
    test "requires role, user_id and organization_id" do
      changeset = Membership.changeset(%Membership{}, %{})
      refute changeset.valid?
      assert %{role: _, user_id: _, organization_id: _} = errors(changeset)
    end

    test "is valid with the required fields" do
      changeset =
        Membership.changeset(%Membership{}, %{
          role: :admin,
          user_id: Ecto.UUID.generate(),
          organization_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end
  end

  describe "tour_changeset/2" do
    test "casts the tour completion timestamp" do
      now = ~U[2026-09-02 12:00:00Z]
      changeset = Membership.tour_changeset(%Membership{}, %{admin_tour_completed_at: now})

      assert Ecto.Changeset.get_change(changeset, :admin_tour_completed_at) == now
    end

    test "ignores unrelated fields" do
      changeset = Membership.tour_changeset(%Membership{}, %{role: :owner})

      assert Ecto.Changeset.get_change(changeset, :role) == nil
    end
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
