defmodule Architex.Room do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Architex.{Repo, Room, Event, Alias, RoomServer, Account}
  alias ArchitexWeb.Client.Request.{CreateRoom, Messages}

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
    has_many :events, Event, foreign_key: :room_id
    has_many :aliases, Alias, foreign_key: :room_id
  end

  @spec changeset(%Room{}, map()) :: Ecto.Changeset.t()
  def changeset(room, params \\ %{}) do
    cast(room, params, [:visibility])
  end

  @spec create_changeset(CreateRoom.t()) :: Ecto.Changeset.t()
  def create_changeset(%CreateRoom{visibility: visibility}) do
    visibility = visibility || :public

    %Room{id: generate_room_id()}
    |> changeset(%{visibility: visibility})
  end

  @spec generate_room_id() :: String.t()
  def generate_room_id do
    "!" <> Architex.random_string(18) <> ":" <> Architex.server_name()
  end

  @spec update_forward_extremities(Event.t(), Room.t()) :: Room.t()
  def update_forward_extremities(
        %Event{
          id: event_id,
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

  @spec create(Account.t(), CreateRoom.t()) :: {:ok, String.t()} | {:error, atom()}
  def create(account, input) do
    with {:ok, %Room{id: room_id}} <- Repo.insert(create_changeset(input)),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      RoomServer.create_room(pid, account, input)
    else
      _ -> {:error, :unknown}
    end
  end

  @spec get_messages(Room.t(), Messages.t()) :: {[Event.t()], integer() | nil, integer() | nil}
  def get_messages(room, %Messages{from: from, to: to, dir: dir, limit: limit}) do
    limit = limit || 10

    events =
      room
      |> Ecto.assoc(:events)
      |> order_by_direction(dir)
      |> events_from(from, dir)
      |> events_to(to, dir)
      |> limit(^limit)
      |> Repo.all()

    {events, get_start(events, dir), get_end(events, limit, dir)}
  end

  @spec order_by_direction(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  defp order_by_direction(query, "b"), do: order_by(query, desc: :origin_server_ts, desc: :nid)
  defp order_by_direction(query, "f"), do: order_by(query, asc: :origin_server_ts, asc: :nid)

  # When 'from' is empty, we return events from the start or end
  # of the room's history.
  @spec events_from(Ecto.Query.t(), String.t(), String.t()) :: Ecto.Query.t()
  defp events_from(query, "", _), do: query

  defp events_from(query, from, "b") do
    from = String.to_integer(from)
    where(query, [e], e.nid < ^from)
  end

  defp events_from(query, from, "f") do
    from = String.to_integer(from)
    where(query, [e], e.nid > ^from)
  end

  @spec events_to(Ecto.Query.t(), String.t() | nil, String.t()) :: Ecto.Query.t()
  defp events_to(query, nil, _), do: query

  defp events_to(query, to, "b") do
    to = String.to_integer(to)
    where(query, [e], e.nid >= ^to)
  end

  defp events_to(query, to, "f") do
    to = String.to_integer(to)
    where(query, [e], e.nid <= ^to)
  end

  @spec get_start([Event.t()], String.t()) :: integer() | nil
  defp get_start([], _), do: nil
  defp get_start([%Event{nid: first_nid} | _], "f"), do: first_nid

  defp get_start(events, "b") do
    %Event{nid: last_nid} = List.last(events)
    last_nid
  end

  @spec get_end([Event.t()], integer(), String.t()) :: integer() | nil
  defp get_end(events, limit, _) when length(events) < limit, do: nil

  defp get_end([%Event{nid: first_nid} | _], _, "f"), do: first_nid

  defp get_end(events, _, "b") do
    %Event{nid: last_nid} = List.last(events)
    last_nid
  end
end
