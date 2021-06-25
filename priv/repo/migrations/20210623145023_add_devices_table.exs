defmodule MatrixServer.Repo.Migrations.AddDevicesTable do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :device_id, :string, primary_key: true, null: false
      add :access_token, :string
      add :display_name, :string

      add :localpart,
          references(:accounts, column: :localpart, on_delete: :delete_all, type: :string),
          primary_key: true,
          null: false
    end

    # Compound primary already indexes device_id.
    create index(:devices, [:localpart])
  end
end
