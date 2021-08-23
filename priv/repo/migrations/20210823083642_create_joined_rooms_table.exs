defmodule MatrixServer.Repo.Migrations.CreateJoinedRoomsTable do
  use Ecto.Migration

  def change do
    create table(:joined_rooms, primary_key: false) do
      add :localpart,
          references(:accounts, column: :localpart, type: :string),
          primary_key: true,
          null: false

      add :room_id, references(:rooms, type: :string),
        primary_key: true,
        null: false
    end
  end
end
