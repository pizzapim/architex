defmodule MatrixServer.RoomServer do
  use GenServer

  alias MatrixServer.{Repo, Room, Event, Account}
  alias MatrixServerWeb.API.CreateRoom

  @registry MatrixServer.RoomServer.Registry
  @supervisor MatrixServer.RoomServer.Supervisor

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def create_room(input, account) do
    %Room{id: room_id} = room = Repo.insert!(Room.create_changeset(input))

    opts = [
      name: {:via, Registry, {@registry, room_id}},
      input: input,
      account: account,
      room: room
    ]

    DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts})
  end

  @impl true
  def init(opts) do
    %Room{id: room_id} = Keyword.fetch!(opts, :room)
    input = Keyword.fetch!(opts, :input)
    account = Keyword.fetch!(opts, :account)

    Repo.transaction(fn ->
      with {:ok, state_set} <- insert_create_room_event(account, input, room_id) do
        {:ok, %{room_id: room_id, state_set: state_set}}
      end
    end)
  end

  defp insert_create_room_event(
         %Account{localpart: localpart},
         %CreateRoom{room_version: room_version},
         room_id
       ) do
    state_set =
      Event.create_room(room_id, MatrixServer.get_mxid(localpart), room_version)
      |> Repo.insert!()
      |> MatrixServer.StateResolution.resolve(true)

    {:ok, state_set}
  end
end
