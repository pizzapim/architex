defmodule MatrixServer.Repo.Migrations.AddAccountsTable do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :localpart, :string, primary_key: true, null: false
      add :password_hash, :string, size: 60, null: false
      timestamps(updated_at: false)
    end
  end
end
