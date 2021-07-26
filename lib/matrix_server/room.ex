defmodule MatrixServer.Room do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias MatrixServer.{Repo, Room, Event}
  alias MatrixServerWeb.API.CreateRoom

  @primary_key {:id, :string, []}
  schema "rooms" do
    field :visibility, Ecto.Enum, values: [:public, :private]
    field :state, :map
    field :forward_extremities, {:array, :string}
    has_many :events, Event, foreign_key: :event_id
  end

  def changeset(room, params \\ %{}) do
    cast(room, params, [:visibility])
  end

  def create_changeset(%CreateRoom{} = input) do
    visibility = input.visibility || :public

    %Room{id: generate_room_id(), forward_extremities: [], state: %{}}
    |> changeset(%{visibility: visibility})
  end

  def generate_room_id do
    "!" <> MatrixServer.random_string(18) <> ":" <> MatrixServer.server_name()
  end

  def update_forward_extremities(
        %Event{
          event_id: event_id,
          prev_events: prev_event_ids
        },
        %Room{id: room_id, forward_extremities: forward_extremities}
      ) do
    new_forward_extremities = [event_id | forward_extremities -- prev_event_ids]

    {_, [room]} =
      from(r in Room, where: r.id == ^room_id, select: r)
      |> Repo.update_all(set: [forward_extremities: new_forward_extremities])

    room
  end
end
