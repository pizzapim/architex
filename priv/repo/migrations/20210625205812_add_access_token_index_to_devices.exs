defmodule MatrixServer.Repo.Migrations.AddAccessTokenIndexToDevices do
  use Ecto.Migration

  def change do
    create index(:devices, [:access_token], unique: true)
  end
end
