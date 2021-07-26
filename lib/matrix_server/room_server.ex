defmodule MatrixServer.RoomServer do
  use GenServer

  import Ecto.Query

  alias MatrixServer.{Repo, Room, Event, Account, StateResolution}
  alias MatrixServerWeb.API.CreateRoom

  @registry MatrixServer.RoomServer.Registry
  @supervisor MatrixServer.RoomServer.Supervisor

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

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    %Room{id: room_id} = room = Keyword.fetch!(opts, :room)
    input = Keyword.fetch!(opts, :input)
    account = Keyword.fetch!(opts, :account)

    state_set = %{}

    Repo.transaction(fn ->
      with {:ok, create_room_event, state_set} <-
             room_creation_create_room(account, input, room, state_set),
           {:ok, join_creator_event, state_set} <-
             room_creation_join_creator(account, room, state_set, create_room_event),
           {:ok, _power_levels_event, state_set} <-
             room_creation_power_levels(
               account,
               room,
               state_set,
               create_room_event,
               join_creator_event
             ) do
        {:ok, %{room_id: room_id, state_set: state_set}}
      else
        _ -> {:error, :something}
      end
    end)
  end

  defp room_creation_create_room(
         %Account{localpart: localpart},
         %CreateRoom{room_version: room_version},
         %Room{id: room_id},
         _state_set
       ) do
    Event.create_room(room_id, MatrixServer.get_mxid(localpart), room_version)
    |> verify_and_insert_event(%{})
  end

  defp room_creation_join_creator(
         %Account{localpart: localpart},
         %Room{id: room_id},
         state_set,
         %Event{event_id: create_room_id}
       ) do
    Event.join(room_id, MatrixServer.get_mxid(localpart))
    |> Map.put(:auth_events, [create_room_id])
    |> Map.put(:prev_events, [create_room_id])
    |> verify_and_insert_event(state_set)
  end

  defp room_creation_power_levels(
         %Account{localpart: localpart},
         %Room{id: room_id},
         state_set,
         %Event{event_id: create_room_id},
         %Event{event_id: join_creator_id}
       ) do
    Event.power_levels(room_id, MatrixServer.get_mxid(localpart))
    |> Map.put(:auth_events, [create_room_id, join_creator_id])
    |> Map.put(:prev_events, [join_creator_id])
    |> verify_and_insert_event(state_set)
  end

  defp verify_and_insert_event(event, current_state_set) do
    # Check the following things:
    # 1. TODO: Is a valid event, otherwise it is dropped.
    # 2. TODO: Passes signature checks, otherwise it is dropped.
    # 3. TODO: Passes hash checks, otherwise it is redacted before being processed further.
    # 4. Passes authorization rules based on the event's auth events, otherwise it is rejected.
    # 5. Passes authorization rules based on the state at the event, otherwise it is rejected.
    # 6. Passes authorization rules based on the current state of the room, otherwise it is "soft failed".
    if Event.prevalidate(event) do
      if StateResolution.is_authorized_by_auth_events(event) do
        state_set = StateResolution.resolve(event, false)

        if StateResolution.is_authorized(event, state_set) do
          if StateResolution.is_authorized(event, current_state_set) do
            # We assume here that the event is always a forward extremity.
            Room.update_forward_extremities(event)
            {:ok, event} = Repo.insert(event)
            state_set = StateResolution.resolve_forward_extremities(event)
            {:ok, event, state_set}
          else
            {:error, :soft_failed}
          end
        else
          {:error, :rejected}
        end
      else
        {:error, :rejected}
      end
    else
      {:error, :invalid}
    end
  end

  def testing do
    account = Repo.one!(from a in Account, limit: 1)
    create_room(%CreateRoom{}, account)
  end
end
