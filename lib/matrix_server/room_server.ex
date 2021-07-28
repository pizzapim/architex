defmodule MatrixServer.RoomServer do
  use GenServer

  import Ecto.Query

  alias MatrixServer.{Repo, Room, Event, StateResolution}
  alias MatrixServerWeb.API.CreateRoom
  alias MatrixServer.StateResolution.Authorization

  @registry MatrixServer.RoomServer.Registry
  @supervisor MatrixServer.RoomServer.Supervisor

  ### Interface

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # Get room server pid, or spin one up for the room.
  # If the room does not exist, return an error.
  def get_room_server(room_id) do
    case Repo.one(from r in Room, where: r.id == ^room_id) do
      nil ->
        {:error, :not_found}

      %Room{} ->
        case Registry.lookup(@registry, room_id) do
          [{pid, _}] ->
            {:ok, pid}

          [] ->
            opts = [
              name: {:via, Registry, {@registry, room_id}},
              room_id: room_id
            ]

            DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts})
        end
    end
  end

  def create_room(pid, account, input) do
    GenServer.call(pid, {:create_room, account, input})
  end

  ### Implementation

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)

    {:ok, %{room_id: room_id, state_set: %{}}}
  end

  @impl true
  def handle_call({:create_room, account, input}, _from, %{room_id: room_id} = state) do
    result =
      Repo.transaction(fn ->
        # TODO: power_level_content_override, initial_state, invite, invite_3pid
        with room <- Repo.one!(from r in Room, where: r.id == ^room_id),
             {:ok, create_room_id, state_set, room} <-
               room_creation_create_room(account, input, room),
             {:ok, join_creator_id, state_set, room} <-
               room_creation_join_creator(account, room, state_set, [create_room_id]),
             {:ok, pl_id, state_set, room} <-
               room_creation_power_levels(
                 account,
                 room,
                 state_set,
                 [create_room_id, join_creator_id]
               ),
             {:ok, _, state_set, room} <-
               room_creation_preset(account, input, room, state_set, [
                 create_room_id,
                 join_creator_id,
                 pl_id
               ]),
             {:ok, _, state_set, room} <-
               room_creation_name(account, input, room, state_set, [
                 create_room_id,
                 join_creator_id,
                 pl_id
               ]),
             {:ok, _, state_set, _} <-
               room_creation_topic(account, input, room, state_set, [
                 create_room_id,
                 join_creator_id,
                 pl_id
               ]) do
          state_set
        else
          reason ->
            Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, state_set} -> {:reply, :ok, %{state | state_set: state_set}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp room_creation_create_room(account, %CreateRoom{room_version: room_version}, room) do
    Event.create_room(room, account, room_version)
    |> verify_and_insert_event(%{}, room)
  end

  defp room_creation_join_creator(account, room, state_set, auth_events) do
    Event.join(room, account)
    |> Map.put(:auth_events, auth_events)
    |> verify_and_insert_event(state_set, room)
  end

  defp room_creation_power_levels(account, room, state_set, auth_events) do
    Event.power_levels(room, account)
    |> Map.put(:auth_events, auth_events)
    |> verify_and_insert_event(state_set, room)
  end

  # TODO: trusted_private_chat:
  # All invitees are given the same power level as the room creator.
  defp room_creation_preset(
         account,
         %CreateRoom{preset: nil},
         %Room{visibility: visibility} = room,
         state_set,
         auth_events
       ) do
    preset =
      case visibility do
        :public -> "public_chat"
        :private -> "private_chat"
      end

    room_creation_preset(account, preset, room, state_set, auth_events)
  end

  defp room_creation_preset(account, %CreateRoom{preset: preset}, room, state_set, auth_events) do
    room_creation_preset(account, preset, room, state_set, auth_events)
  end

  defp room_creation_preset(account, preset, room, state_set, auth_events) do
    {join_rule, his_vis, guest_access} =
      case preset do
        "private_chat" -> {"invite", "shared", "can_join"}
        "trusted_private_chat" -> {"invite", "shared", "can_join"}
        "public_chat" -> {"public", "shared", "forbidden"}
      end

    with {:ok, _, _, _} <-
           room_creation_join_rules(account, join_rule, room, state_set, auth_events),
         {:ok, _, _, _} <- room_creation_his_vis(account, his_vis, room, state_set, auth_events) do
      room_creation_guest_access(account, guest_access, room, state_set, auth_events)
    end
  end

  defp room_creation_join_rules(account, join_rule, room, state_set, auth_events) do
    Event.join_rules(room, account, join_rule)
    |> Map.put(:auth_events, auth_events)
    |> verify_and_insert_event(state_set, room)
  end

  defp room_creation_his_vis(account, his_vis, room, state_set, auth_events) do
    Event.history_visibility(room, account, his_vis)
    |> Map.put(:auth_events, auth_events)
    |> verify_and_insert_event(state_set, room)
  end

  defp room_creation_guest_access(account, guest_access, room, state_set, auth_events) do
    Event.guest_access(room, account, guest_access)
    |> Map.put(:auth_events, auth_events)
    |> verify_and_insert_event(state_set, room)
  end

  defp room_creation_name(_, %CreateRoom{name: nil}, room, state_set, _) do
    {:ok, nil, state_set, room}
  end

  defp room_creation_name(account, %CreateRoom{name: name}, room, state_set, auth_events) do
    Event.name(room, account, name)
    |> Map.put(:auth_events, auth_events)
    |> verify_and_insert_event(state_set, room)
  end

  defp room_creation_topic(_, %CreateRoom{topic: nil}, room, state_set, _) do
    {:ok, nil, state_set, room}
  end

  defp room_creation_topic(account, %CreateRoom{topic: topic}, room, state_set, auth_events) do
    Event.topic(room, account, topic)
    |> Map.put(:auth_events, auth_events)
    |> verify_and_insert_event(state_set, room)
  end

  defp verify_and_insert_event(
         %Event{event_id: event_id} = event,
         current_state_set,
         %Room{forward_extremities: forward_extremities} = room
       ) do
    # Check the following things:
    # 1. TODO: Is a valid event, otherwise it is dropped.
    # 2. TODO: Passes signature checks, otherwise it is dropped.
    # 3. TODO: Passes hash checks, otherwise it is redacted before being processed further.
    # 4. Passes authorization rules based on the event's auth events, otherwise it is rejected.
    # 5. Passes authorization rules based on the state at the event, otherwise it is rejected.
    # 6. Passes authorization rules based on the current state of the room, otherwise it is "soft failed".
    event = %Event{event | prev_events: forward_extremities}

    if Event.prevalidate(event) do
      if Authorization.authorized_by_auth_events?(event) do
        state_set = StateResolution.resolve(event, false)

        if Authorization.authorized?(event, state_set) do
          if Authorization.authorized?(event, current_state_set) do
            # We assume here that the event is always a forward extremity.
            room = Room.update_forward_extremities(event, room)
            {:ok, event} = Repo.insert(event)
            state_set = StateResolution.resolve_forward_extremities(event)
            {:ok, event_id, state_set, room}
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
end
