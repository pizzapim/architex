defmodule MatrixServer.Room do
  use Ecto.Schema

  import Ecto.Changeset

  alias MatrixServer.{Room, Event}
  alias MatrixServerWeb.API.CreateRoom

  @primary_key {:id, :string, []}
  schema "rooms" do
    field :visibility, Ecto.Enum, values: [:public, :private]
    has_many :events, Event, foreign_key: :event_id
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
