defmodule MatrixServer.Repo.Migrations.MoveTimestampsToIntsAgain do
  use Ecto.Migration

  def change do
    alter table(:events) do
      remove :origin_server_ts, :utc_datetime_usec, null: false
      add :origin_server_ts, :bigint, null: false
    end

    alter table(:server_key_info) do
      remove :valid_until, :utc_datetime_usec, null: false
      add :valid_until, :bigint, default: 0, null: false
    end
  end
end
