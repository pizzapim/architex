defmodule MatrixServer.Repo.Migrations.CreateSigningKeyAndServerKeyInfoTable do
  use Ecto.Migration

  def change do
    create table(:server_key_info, primary_key: false) do
      add :server_name, :string, primary_key: true, null: false
      add :valid_until, :bigint, default: 0, null: false
    end

    create table(:signing_keys, primary_key: false) do
      add :server_name,
          references(:server_key_info, column: :server_name, type: :string, on_delete: :delete_all),
          null: false

      add :signing_key_id, :string, primary_key: true, null: false
      add :signing_key, :binary, null: false
    end
  end
end
