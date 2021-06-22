defmodule MatrixServer.Repo do
  use Ecto.Repo,
    otp_app: :matrix_server,
    adapter: Ecto.Adapters.Postgres
end
