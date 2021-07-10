defmodule MatrixServer.Room do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias MatrixServerWeb.API.CreateRoom
  alias Ecto.Multi

  @primary_key {:id, :string, []}
  schema "rooms" do
    field :visibility, Ecto.Enum, values: [:public, :private]
  end

  def create(%CreateRoom{} = api) do
    Multi.new()
    |> Multi.insert(:room, Room.create_changeset(api))
  end

  def changeset(room, params \\ %{}) do
    room
    |> cast(params, [:visibility])
  end

  def create_changeset(%CreateRoom{} = api) do
    %Room{visibility: api.visibility, id: MatrixServer.random_string(18)}
    |> changeset()
  end
end
