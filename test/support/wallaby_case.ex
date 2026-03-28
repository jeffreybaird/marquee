defmodule BobineWeb.WallabyCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.DSL
      import Wallaby.Query
      import Bobine.Factory

      alias BobineWeb.Endpoint

      @endpoint BobineWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Bobine.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Bobine.Repo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Bobine.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    {:ok, session: session}
  end
end
