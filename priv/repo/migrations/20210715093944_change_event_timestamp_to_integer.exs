defmodule MatrixServer.Repo.Migrations.ChangeEventTimestampToInteger do
  use Ecto.Migration

  def change do
    alter table(:events) do
      remove :timestamp, :string, null: false
      add :origin_server_ts, :integer, null: false
    end
  end
end
