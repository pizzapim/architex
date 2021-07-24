defmodule MatrixServer.RoomServer do
  use GenServer

  import Ecto.Query

  alias MatrixServer.{Repo, Room, Event, Account, StateResolution}
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
    create_room_event = Event.create_room(room_id, MatrixServer.get_mxid(localpart), room_version)
    verify_event(create_room_event)
    |> IO.inspect()

    {:ok, %{}}
  end

  defp verify_event(%Event{auth_events: auth_event_ids} = event) do
    # Check the following things:
    # 1. TODO: Is a valid event, otherwise it is dropped.
    # 2. TODO: Passes signature checks, otherwise it is dropped.
    # 3. TODO: Passes hash checks, otherwise it is redacted before being processed further.
    # 4. Passes authorization rules based on the event's auth events, otherwise it is rejected.
    # 5. Passes authorization rules based on the state at the event, otherwise it is rejected.
    # 6. TODO: Passes authorization rules based on the current state of the room, otherwise it is "soft failed".
    if StateResolution.is_authorized_by_auth_events(event) do
      auth_events =
        Event
        |> where([e], e.event_id in ^auth_event_ids)
        |> select([e], {e.event_id, e})
        |> Repo.all()
        |> Enum.into(%{})
      # TODO: make the state set a mapping to Event struct.
      state_set = StateResolution.resolve(event, false)
      StateResolution.is_authorized(event, state_set, auth_events)
    else
      false
    end
  end
end
