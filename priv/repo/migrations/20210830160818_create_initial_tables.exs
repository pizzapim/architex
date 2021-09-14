defmodule Architex.Repo.Migrations.CreateInitialTables do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :localpart, :string, null: false
      add :password_hash, :string, size: 60, null: false
      add :avatar_url, :string, null: true
      add :displayname, :string, null: true
      timestamps(updated_at: false)
    end

    create index(:accounts, [:localpart], unique: true)

    create table(:rooms, primary_key: false) do
      add :id, :string, primary_key: true
      add :state_set, {:array, :string}, default: [], null: false
      add :forward_extremities, {:array, :string}, default: [], null: false
      add :visibility, :string, null: false, default: "public"
    end

    create table(:events, primary_key: false) do
      add :nid, :serial, primary_key: true
      add :id, :string, null: false

      # PDU Fields
      add :auth_events, {:array, :string}, null: false
      add :content, :map, null: false
      add :depth, :integer, null: false
      add :hashes, :map, null: false
      add :origin, :string, null: false
      add :origin_server_ts, :bigint, null: false
      add :prev_events, {:array, :string}, null: false
      add :redacts, :string, null: true
      add :room_id, references(:rooms, type: :string), null: false
      add :sender, :string, null: false
      add :signatures, :map, null: false
      add :state_key, :string, null: true
      add :type, :string, null: false
      add :unsigned, :map, null: true
    end

    create index(:events, [:id], unique: true)
    create index(:events, [:origin_server_ts])

    create table(:server_key_info, primary_key: false) do
      add :valid_until, :bigint, default: 0, null: false
      add :server_name, :string, primary_key: true
    end

    create table(:signing_keys, primary_key: false) do
      add :server_name,
          references(:server_key_info, column: :server_name, type: :string, on_delete: :delete_all),
          null: false

      add :signing_key_id, :string, primary_key: true
      add :signing_key, :binary, null: false
    end

    create table(:aliases, primary_key: false) do
      add :alias, :string, primary_key: true
      add :room_id, references(:rooms, type: :string, on_delete: :delete_all), null: false
    end

    create index(:aliases, [:room_id])

    create table(:devices, primary_key: false) do
      add :nid, :serial, primary_key: true
      add :id, :string, null: false
      add :access_token, :string, null: false
      add :display_name, :string

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
    end

    create index(:devices, [:id, :account_id], unique: true)
    create index(:devices, [:account_id])
    create index(:devices, [:access_token], unique: true)

    create table(:device_transactions, primary_key: false) do
      add :txn_id, :string, primary_key: true

      add :device_nid, references(:devices, column: :nid, on_delete: :delete_all),
        primary_key: true

      add :event_id, :string, null: false
    end

    create table(:membership, primary_key: false) do
      add :account_id, references(:accounts), primary_key: true
      add :room_id, references(:rooms, type: :string), primary_key: true
      add :membership, :string, null: false
    end
  end
end
