defmodule MatrixServer.Repo.Migrations.ChangeRoomStateToArray do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      remove :state, :map, default: %{}, null: false
      add :state, {:array, {:array, :string}}, default: [], null: false
    end
  end
end
