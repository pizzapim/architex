defmodule Architex.Room do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Architex.{Repo, Room, Event, Alias, RoomServer}
  alias ArchitexWeb.Client.Request.CreateRoom

  @type t :: %__MODULE__{
          visibility: :public | :private,
          state: list(list(String.t())),
          forward_extremities: list(String.t())
        }

  @primary_key {:id, :string, []}
  schema "rooms" do
    field :visibility, Ecto.Enum, values: [:public, :private]
    field :state, {:array, {:array, :string}}
    field :forward_extremities, {:array, :string}
    has_many :events, Event, foreign_key: :event_id
    has_many :aliases, Alias, foreign_key: :room_id
  end

  def changeset(room, params \\ %{}) do
    cast(room, params, [:visibility])
  end

  def create_changeset(%CreateRoom{visibility: visibility}) do
    visibility = visibility || :public

    %Room{id: generate_room_id()}
    |> changeset(%{visibility: visibility})
  end

  def generate_room_id do
    "!" <> Architex.random_string(18) <> ":" <> Architex.server_name()
  end

  def update_forward_extremities(
        %Event{
          event_id: event_id,
          prev_events: prev_event_ids
        },
        %Room{id: room_id, forward_extremities: forward_extremities}
      ) do
    new_forward_extremities = [event_id | forward_extremities -- prev_event_ids]

    # TODO: might not need to save to DB here.
    {_, [room]} =
      from(r in Room, where: r.id == ^room_id, select: r)
      |> Repo.update_all(set: [forward_extremities: new_forward_extremities])

    room
  end

  def create(account, input) do
    with {:ok, %Room{id: room_id}} <- Repo.insert(create_changeset(input)),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      RoomServer.create_room(pid, account, input)
    else
      _ -> {:error, :unknown}
    end
  end
end
