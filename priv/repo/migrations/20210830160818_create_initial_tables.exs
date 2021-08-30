defmodule MatrixServer.Repo.Migrations.CreateInitialTables do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :localpart, :string, primary_key: true, null: false
      add :password_hash, :string, size: 60, null: false
      timestamps(updated_at: false)
    end

    create table(:rooms, primary_key: false) do
      add :state, {:array, {:array, :string}}, default: [], null: false
      add :forward_extremities, {:array, :string}, default: [], null: false
      add :id, :string, primary_key: true, null: false
      add :visibility, :string, null: false, default: "public"
    end

    create table(:joined_rooms, primary_key: false) do
      add :localpart,
          references(:accounts, column: :localpart, type: :string),
          primary_key: true,
          null: false

      add :room_id, references(:rooms, type: :string),
        primary_key: true,
        null: false
    end

    create table(:events, primary_key: false) do
      add :origin_server_ts, :bigint, null: false
      add :unsigned, :map, default: %{}, null: true
      add :hashes, :map, null: false
      add :signatures, :map, null: false
      add :event_id, :string, null: false
      add :content, :map
      add :type, :string, null: false
      add :state_key, :string
      add :sender, :string, null: false
      add :prev_events, {:array, :string}, null: false
      add :auth_events, {:array, :string}, null: false
      add :room_id, references(:rooms, type: :string), null: false
    end

    create table(:server_key_info, primary_key: false) do
      add :valid_until, :bigint, default: 0, null: false
      add :server_name, :string, primary_key: true, null: false
    end

    create table(:signing_keys, primary_key: false) do
      add :server_name,
          references(:server_key_info, column: :server_name, type: :string, on_delete: :delete_all),
          null: false

      add :signing_key_id, :string, primary_key: true, null: false
      add :signing_key, :binary, null: false
    end

    create table(:aliases, primary_key: false) do
      add :alias, :string, primary_key: true, null: false
      add :room_id, references(:rooms, type: :string, on_delete: :delete_all), null: false
    end

    create index(:aliases, [:room_id])

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

    create index(:devices, [:access_token], unique: true)
  end
end
