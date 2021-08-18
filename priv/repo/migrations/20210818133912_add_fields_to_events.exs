defmodule MatrixServer.Repo.Migrations.AddFieldsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :unsigned, :map, default: %{}, null: true
      add :hashes, :map, null: false
      add :signatures, :map, null: false
    end
  end
end
