defmodule MatrixServer.Repo.Migrations.AddStateToRoom do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :state, :map, default: %{}, null: false
    end
  end
end
