defmodule MatrixServer.RoomServer do
  use GenServer

  import Ecto.Query
  import Ecto.Changeset

  alias MatrixServer.{Repo, Room, Event, StateResolution}
  alias MatrixServer.StateResolution.Authorization
  alias MatrixServerWeb.Client.Request.CreateRoom

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

      %Room{state: serialized_state_set} ->
        case Registry.lookup(@registry, room_id) do
          [{pid, _}] ->
            {:ok, pid}

          [] ->
            opts = [
              name: {:via, Registry, {@registry, room_id}},
              room_id: room_id,
              serialized_state_set: serialized_state_set
            ]

            DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts})
        end
    end
  end

  def create_room(pid, account, input) do
    GenServer.call(pid, {:create_room, account, input})
  end

  def server_in_room(pid, domain) do
    GenServer.call(pid, {:server_in_room, domain})
  end

  ### Implementation

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    serialized_state_set = Keyword.fetch!(opts, :serialized_state_set)
    state_event_ids = Enum.map(serialized_state_set, fn [_, _, event_id] -> event_id end)

    state_set =
      Event
      |> where([e], e.event_id in ^state_event_ids)
      |> Repo.all()
      |> Enum.into(%{}, fn %Event{type: type, state_key: state_key} = event ->
        {{type, state_key}, event}
      end)

    {:ok, %{room_id: room_id, state_set: state_set}}
  end

  @impl true
  def handle_call(
        {:create_room, account,
         %CreateRoom{room_version: room_version, name: name, topic: topic, preset: preset}},
        _from,
        %{room_id: room_id} = state
      ) do
    result =
      Repo.transaction(fn ->
        room = Repo.one!(from r in Room, where: r.id == ^room_id)
        create_room = Event.create_room(room, account, room_version)
        join_creator = Event.join(room, account, [create_room.event_id])
        pls = Event.power_levels(room, account, [create_room.event_id, join_creator.event_id])
        auth_events = [create_room.event_id, join_creator.event_id, pls.event_id]
        name_event = if name, do: Event.name(room, account, name, auth_events)
        topic_event = if topic, do: Event.topic(room, account, topic, auth_events)

        # TODO: power_level_content_override, initial_state, invite, invite_3pid
        events =
          [create_room, join_creator, pls] ++
            room_creation_preset(account, preset, room, auth_events) ++
            [name_event, topic_event]

        result =
          events
          |> Enum.reject(&Kernel.is_nil/1)
          |> Enum.reduce_while({%{}, room}, fn event, {state_set, room} ->
            case verify_and_insert_event(event, state_set, room) do
              {:ok, state_set, room} -> {:cont, {state_set, room}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case result do
          {:error, reason} ->
            Repo.rollback(reason)

          {state_set, room} ->
            serialized_state_set =
              Enum.map(state_set, fn {{type, state_key}, event} ->
                [type, state_key, event.event_id]
              end)

            Repo.update!(change(room, state: serialized_state_set))
            state_set
        end
      end)

    case result do
      {:ok, state_set} -> {:reply, {:ok, room_id}, %{state | state_set: state_set}}
      {:error, reason} -> {:reply, {:error, reason}, state}
      _ -> {:reply, {:error, :unknown}, state}
    end
  end

  def handle_call({:server_in_room, domain}, _from, %{state_set: state_set} = state) do
    result = Enum.any?(state_set, fn
      {{"m.room.member", user_id}, %Event{content: %{"membership" => "join"}}} ->
        MatrixServer.get_domain(user_id) == domain

      _ ->
        false
    end)

    {:reply, result, state}
  end

  # TODO: trusted_private_chat:
  # All invitees are given the same power level as the room creator.
  defp room_creation_preset(account, nil, %Room{visibility: visibility} = room, auth_events) do
    preset =
      case visibility do
        :public -> "public_chat"
        :private -> "private_chat"
      end

    room_creation_preset(account, preset, room, auth_events)
  end

  defp room_creation_preset(account, preset, room, auth_events) do
    {join_rule, his_vis, guest_access} =
      case preset do
        "private_chat" -> {"invite", "shared", "can_join"}
        "trusted_private_chat" -> {"invite", "shared", "can_join"}
        "public_chat" -> {"public", "shared", "forbidden"}
      end

    [
      Event.join_rules(room, account, join_rule, auth_events),
      Event.history_visibility(room, account, his_vis, auth_events),
      Event.guest_access(room, account, guest_access, auth_events)
    ]
  end

  defp verify_and_insert_event(
         event,
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

    with true <- Event.prevalidate(event),
         true <- Authorization.authorized_by_auth_events?(event),
         state_set <- StateResolution.resolve(event, false),
         true <- Authorization.authorized?(event, state_set),
         true <- Authorization.authorized?(event, current_state_set) do
      room = Room.update_forward_extremities(event, room)
      event = Repo.insert!(event)
      state_set = StateResolution.resolve_forward_extremities(event)
      {:ok, state_set, room}
    else
      _ -> {:error, :authorization}
    end
  end
end
