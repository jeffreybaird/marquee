defmodule Marquee.AuditFilterOptionsCacheTest do
  @moduledoc """
  Regression contract for the audit-log filter options cache (E7).

  `Audit.get_filter_options/1` and `Audit.get_filter_options_global/0` are
  cached for five minutes. Once warmed, a new audit entry with a new action,
  resource type, or organization must still appear in the filter options
  the next time they are read; the cache must be invalidated when audit
  entries are written, not merely expire.
  """

  # The global filter-options key is shared ETS state, so run serially.
  use Marquee.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Marquee.Accounts.Scope
  alias Marquee.Audit
  alias Marquee.Cache
  alias Marquee.Content
  alias Marquee.Events
  alias Marquee.Events.AuditSubscriber
  alias Marquee.Repo

  setup do
    Cache.delete("audit_filter_options:global")
    on_exit(fn -> Cache.delete("audit_filter_options:global") end)
    :ok
  end

  defp owner_scope(org) do
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :owner)
    Scope.for_user(user) |> Scope.with_organization(org, membership)
  end

  describe "get_filter_options/1 after a new audit entry" do
    test "lists the new action and resource type once the options were already cached" do
      org = insert(:organization)
      scope = owner_scope(org)
      video = insert(:video, organization: org)
      {:ok, _} = Audit.log(scope, "video.created", video)

      warmed = Audit.get_filter_options(org)
      assert "video.created" in warmed.actions
      refute "tag.created" in warmed.actions

      # A real context mutation writes the audit entry.
      assert {:ok, _tag} = Content.create_tag(scope, %{name: "cache regression tag"})

      options = Audit.get_filter_options(org)
      assert "tag.created" in options.actions
      assert "Tag" in options.resource_types
    end
  end

  describe "get_filter_options_global/0 after an event recorded by AuditSubscriber" do
    test "lists the new organization, action and resource type once the options were already cached" do
      subscriber = start_supervised!({AuditSubscriber, []})
      Sandbox.allow(Repo, self(), subscriber)

      org_a = insert(:organization)
      video = insert(:video, organization: org_a)
      {:ok, _} = Audit.log(owner_scope(org_a), "video.created", video)

      warmed = Audit.get_filter_options_global()
      assert org_a.id in Enum.map(warmed.organizations, & &1.id)

      org_b = insert(:organization)
      tag = insert(:tag, organization: org_b)
      Events.broadcast(owner_scope(org_b), {:tag_deleted, tag})

      # Drain the subscriber's mailbox so its audit write has happened.
      _ = :sys.get_state(subscriber)

      assert Repo.exists?(
               from(l in Marquee.Audit.Log,
                 where: l.action == "tag.deleted" and l.organization_id == ^org_b.id
               )
             ),
             "precondition: AuditSubscriber should have recorded tag.deleted"

      options = Audit.get_filter_options_global()
      assert org_b.id in Enum.map(options.organizations, & &1.id)
      assert "tag.deleted" in options.actions
      assert "Tag" in options.resource_types
    end
  end
end
