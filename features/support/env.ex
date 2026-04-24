defmodule BobineFeatures.Support.Env do
  @moduledoc """
  Scenario-level setup for Wallaby E2E step definitions.

  Each scenario checks out a DB connection, flips the sandbox into shared
  mode so the Phoenix endpoint (served from a separate process) can see the
  same data, and spins up a Wallaby session tagged with that connection's
  metadata. `world.session` is the Wallaby session the step defs drive.

  Run with `MIX_ENV=test mix cucumber`.
  """

  use Cucumberex.Hooks.DSL

  before_all_ fn ->
    {:ok, _} = Application.ensure_all_started(:wallaby)
    Ecto.Adapters.SQL.Sandbox.mode(Bobine.Repo, :manual)
  end

  before_ fn world ->
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Bobine.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Bobine.Repo, {:shared, self()})

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Bobine.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    Map.put(world, :session, session)
  end

  after_ fn world ->
    if session = Map.get(world, :session) do
      Wallaby.end_session(session)
    end

    Ecto.Adapters.SQL.Sandbox.checkin(Bobine.Repo)
    world
  end
end
