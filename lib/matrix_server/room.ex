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

  def changeset(room, params \\ %{}) do
    cast(room, params, [:visibility])
  end

  def create_changeset(%CreateRoom{} = input) do
    visibility = input.visibility || :public

    %Room{}
    |> changeset(%{visibility: visibility})
    |> put_change(:id, generate_room_id())
  end

  def generate_room_id do
    "!" <> MatrixServer.random_string(18) <> "@" <> MatrixServer.server_name()
  end
end
