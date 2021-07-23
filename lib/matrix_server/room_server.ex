defmodule MatrixServer.RoomServer do
  use GenServer

  alias MatrixServer.{Repo, Room, Event, Account}
  alias MatrixServerWeb.API.CreateRoom
  alias Ecto.Multi

  @registry MatrixServer.RoomServer.Registry
  @supervisor MatrixServer.RoomServer.Supervisor

  def get_room_server(room_id) do
    case Registry.lookup(@registry, room_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        opts = [
          room_id: room_id,
          name: {:via, Registry, {@registry, room_id}}
        ]

        DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts})
    end
  end

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def create_room(input, account) do
    Multi.new()
    |> Multi.insert(:room, Room.create_changeset(input))
    |> Multi.run(:room_server, fn _repo, %{room: %Room{id: room_id} = room} ->
      opts = [
        name: {:via, Registry, {@registry, room_id}},
        input: input,
        account: account,
        room: room
      ]

      DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts})
    end)
    |> Repo.transaction()
  end

  @impl true
  def init(opts) do
    %Room{id: room_id} = Keyword.fetch!(opts, :room)
    input = Keyword.fetch!(opts, :input)
    account = Keyword.fetch!(opts, :account)

    state = %{
      room_id: room_id,
      state_set: %{}
    }

    Repo.transaction(fn ->
      with {:ok, create_room_event} <- insert_create_room_event(account, input, state) do
        {:ok, state}
      end
    end)

    {:ok, state}
  end

  defp insert_create_room_event(
         %Account{localpart: localpart},
         %CreateRoom{room_version: room_version},
         %{room_id: room_id, state_set: state_set}
       ) do
    create_room_event = Event.create_room(room_id, MatrixServer.get_mxid(localpart), room_version)
    MatrixServer.StateResolution.resolve(create_room_event)
    {:ok, create_room_event}
  end
end
