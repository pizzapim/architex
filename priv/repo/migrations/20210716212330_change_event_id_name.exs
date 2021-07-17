defmodule MatrixServer.Repo.Migrations.ChangeEventIdName do
  use Ecto.Migration

  def change do
    rename table(:events), :id, to: :event_id
  end
end
