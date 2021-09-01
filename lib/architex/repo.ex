defmodule Architex.Repo do
  use Ecto.Repo,
    otp_app: :architex,
    adapter: Ecto.Adapters.Postgres
end
