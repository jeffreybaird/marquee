defmodule Bobine.Repo do
  use Ecto.Repo,
    otp_app: :bobine,
    adapter: Ecto.Adapters.Postgres
end
