defmodule MatrixServer.Repo.Migrations.CreateAliasesTable do
  use Ecto.Migration

  def change do
    create table(:aliases, primary_key: false) do
      add :alias, :string, primary_key: true, null: false
      add :room_id, references(:rooms, type: :string, on_delete: :delete_all), null: false
    end

    create index(:aliases, [:room_id])
  end
end
