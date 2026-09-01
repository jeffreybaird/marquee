{:ok, _} = Application.ensure_all_started(:wallaby)
ExUnit.start(exclude: [:e2e])
Ecto.Adapters.SQL.Sandbox.mode(Marquee.Repo, :manual)
