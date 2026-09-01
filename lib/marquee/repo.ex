defmodule Marquee.Repo do
  use Ecto.Repo,
    otp_app: :marquee,
    adapter: Ecto.Adapters.Postgres
end
