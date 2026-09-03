defmodule Marquee.Accounts.PageTourCompletion do
  @moduledoc """
  Records that a person has seen the first-visit walkthrough for one admin (or,
  in future, viewer) page.

  Scoped per user, per organization, per page key. Unlike the single dashboard
  guided tour (stored on the membership), this table is audience-agnostic: it is
  keyed by `user_id` + `organization_id`, not by membership, so a viewer/
  subscriber — who has no membership — can be given page tours through exactly
  the same table. The page key is a code-level string (e.g. `"content"`), not a
  foreign key to a table of pages: tours only exist where step data exists in
  the frontend.

  The "seen" timestamp is `inserted_at` — first-seen semantics. Re-visiting a
  page never refreshes it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "page_tour_completions" do
    field :page_key, :string

    belongs_to :user, Marquee.Accounts.User
    belongs_to :organization, Marquee.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a page tour completion.

      iex> cs = Marquee.Accounts.PageTourCompletion.changeset(
      ...>   %Marquee.Accounts.PageTourCompletion{},
      ...>   %{user_id: "u1", organization_id: "o1", page_key: "content"}
      ...> )
      iex> cs.valid?
      true

      iex> cs = Marquee.Accounts.PageTourCompletion.changeset(
      ...>   %Marquee.Accounts.PageTourCompletion{}, %{page_key: "content"}
      ...> )
      iex> cs.valid?
      false
  """
  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:user_id, :organization_id, :page_key])
    |> validate_required([:user_id, :organization_id, :page_key])
    |> unique_constraint([:user_id, :organization_id, :page_key],
      name: :page_tour_completions_user_org_page_unique
    )
  end
end
