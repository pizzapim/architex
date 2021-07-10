defmodule MatrixServer.Repo.Migrations.AddEventsAndRoomsTable do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :string, primary_key: true, null: false
      add :visibility, :string, null: false, default: "public"
    end

    create table(:events, primary_key: false) do
      add :id, :string, primary_key: true, null: false
      add :type, :string, null: false
      add :timestamp, :naive_datetime, null: false
      add :state_key, :string
      add :sender, :string, null: false
      add :content, :string
      add :prev_events, {:array, :string}, null: false
      add :auth_events, {:array, :string}, null: false
      add :room_id, references(:rooms, type: :string), null: false
    end
  end
end
