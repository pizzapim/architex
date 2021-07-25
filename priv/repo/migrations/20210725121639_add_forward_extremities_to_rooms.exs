defmodule MatrixServer.Repo.Migrations.AddForwardExtremitiesToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :forward_extremities, {:array, :string}, default: [], null: false
    end
  end
end
