defmodule MatrixServer.RoomServer do
  @moduledoc """
  A GenServer to hold and manipulate the state of a Matrix room.

  Each RoomServer corresponds to one Matrix room that the homeserver participates in.
  The RoomServers are supervised by a DynamicSupervisor RoomServer.Supervisor.
  """

  @typep t :: map()

  use GenServer

  import Ecto.Query
  import Ecto.Changeset

  alias MatrixServer.{Repo, Room, Event, StateResolution, Account, JoinedRoom}
  alias MatrixServer.StateResolution.Authorization
  alias MatrixServerWeb.Client.Request.{CreateRoom, Kick}

  @registry MatrixServer.RoomServer.Registry
  @supervisor MatrixServer.RoomServer.Supervisor

  ### Interface

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Get the PID of the RoomServer for a room.

  If the given room has no running RoomServer yet, it is created.
  If the given room does not exist, an error is returned.
  """
  @spec get_room_server(String.t()) :: {:error, :not_found} | DynamicSupervisor.on_start_child()
  def get_room_server(room_id) do
    # TODO: Might be wise to use a transaction here to prevent race conditions.
    case Repo.one(from r in Room, where: r.id == ^room_id) do
      %Room{state: serialized_state_set} = room ->
        case Registry.lookup(@registry, room_id) do
          [{pid, _}] ->
            {:ok, pid}

          [] ->
            opts = [
              name: {:via, Registry, {@registry, room_id}},
              room: room,
              serialized_state_set: serialized_state_set
            ]

            DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts})
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Create a new Matrix room.

  The new room is created with the given `account` as creator.
  Events are inserted into the new room depending on the input `input` and according
  to the [Matrix documentation](https://matrix.org/docs/spec/client_server/r0.6.1#post-matrix-client-r0-createroom).
  """
  @spec create_room(pid(), Account.t(), CreateRoom.t()) :: {:ok, String.t()} | {:error, atom()}
  def create_room(pid, account, input) do
    GenServer.call(pid, {:create_room, account, input})
  end

  @doc """
  Check whether the given server participates in a room.

  Check whether any participant of the room has a server name matching
  the given `domain`.
  """
  @spec server_in_room?(pid(), String.t()) :: boolean()
  def server_in_room?(pid, domain) do
    GenServer.call(pid, {:server_in_room?, domain})
  end

  @doc """
  Get the state of a room, before the given event was inserted.

  Return a list of all state events and the auth chain.
  """
  @spec get_state_at_event(pid(), Event.t()) :: {[Event.t()], [Event.t()]}
  def get_state_at_event(pid, event) do
    GenServer.call(pid, {:get_state_at_event, event})
  end

  @doc """
  Same as `get_state_at_event/2`, except returns the lists as event IDs.
  """
  @spec get_state_ids_at_event(pid(), Event.t()) :: {[String.t()], [String.t()]}
  def get_state_ids_at_event(pid, event) do
    GenServer.call(pid, {:get_state_ids_at_event, event})
  end

  @doc """
  Invite the a user to this room.
  """
  @spec invite(pid(), Account.t(), String.t()) :: :ok | {:error, atom()}
  def invite(pid, account, user_id) do
    GenServer.call(pid, {:invite, account, user_id})
  end

  @doc """
  Join a room.
  """
  @spec join(pid(), Account.t()) :: {:ok, String.t()} | {:error, atom()}
  def join(pid, account) do
    GenServer.call(pid, {:join, account})
  end

  @doc """
  Leave a room.
  """
  @spec leave(pid(), Account.t()) :: :ok | {:error, atom()}
  def leave(pid, account) do
    GenServer.call(pid, {:leave, account})
  end

  @doc """
  Kick a user from this room.
  """
  @spec kick(pid(), Account.t(), Kick.t()) :: :ok | {:error, atom()}
  def kick(pid, account, request) do
    GenServer.call(pid, {:kick, account, request})
  end

  ### Implementation

  @impl true
  def init(opts) do
    room = Keyword.fetch!(opts, :room)
    serialized_state_set = Keyword.fetch!(opts, :serialized_state_set)
    state_event_ids = Enum.map(serialized_state_set, fn [_, _, event_id] -> event_id end)

    state_set =
      Event
      |> where([e], e.event_id in ^state_event_ids)
      |> Repo.all()
      |> Enum.into(%{}, fn %Event{type: type, state_key: state_key} = event ->
        {{type, state_key}, event}
      end)

    {:ok, %{room: room, state_set: state_set}}
  end

  @impl true
  def handle_call(
        {:create_room, account, input},
        _from,
        %{room: %Room{id: room_id} = room} = state
      ) do
    # TODO: power_level_content_override, initial_state, invite, invite_3pid
    case Repo.transaction(create_room_insert_events(room, account, input)) do
      {:ok, {state_set, room}} ->
        {:reply, {:ok, room_id}, %{state | state_set: state_set, room: room}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      _ ->
        {:reply, {:error, :unknown}, state}
    end
  end

  def handle_call({:server_in_room?, domain}, _from, %{state_set: state_set} = state) do
    result =
      Enum.any?(state_set, fn
        {{"m.room.member", user_id}, %Event{content: %{"membership" => "join"}}} ->
          MatrixServer.get_domain(user_id) == domain

        _ ->
          false
      end)

    {:reply, result, state}
  end

  def handle_call({:get_state_at_event, %Event{room_id: room_id} = event}, _from, state) do
    room_events =
      Event
      |> where([e], e.room_id == ^room_id)
      |> select([e], {e.event_id, e})
      |> Repo.all()
      |> Enum.into(%{})

    state_set = StateResolution.resolve(event, false)
    state_events = Map.values(state_set)

    auth_chain =
      state_set
      |> Map.values()
      |> StateResolution.full_auth_chain(room_events)
      |> Enum.map(&room_events[&1])

    {:reply, {state_events, auth_chain}, state}
  end

  def handle_call({:get_state_ids_at_event, %Event{room_id: room_id} = event}, _from, state) do
    room_events =
      Event
      |> where([e], e.room_id == ^room_id)
      |> select([e], {e.event_id, e})
      |> Repo.all()
      |> Enum.into(%{})

    state_set = StateResolution.resolve(event, false)
    state_events = Enum.map(state_set, fn {_, %Event{event_id: event_id}} -> event_id end)

    auth_chain =
      state_set
      |> Map.values()
      |> StateResolution.full_auth_chain(room_events)
      |> MapSet.to_list()

    {:reply, {state_events, auth_chain}, state}
  end

  def handle_call({:invite, account, user_id}, _from, %{room: room, state_set: state_set} = state) do
    invite_event = Event.invite(room, account, user_id)

    case insert_single_event(room, state_set, invite_event) do
      {:ok, {state_set, room}} -> {:reply, :ok, %{state | state_set: state_set, room: room}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:join, account},
        _from,
        %{room: %Room{id: room_id} = room, state_set: state_set} = state
      ) do
    join_event = Event.join(room, account)

    case insert_single_event(room, state_set, join_event) do
      {:ok, {state_set, room}} ->
        {:reply, {:ok, room_id}, %{state | state_set: state_set, room: room}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:leave, account}, _from, %{room: room, state_set: state_set} = state) do
    leave_event = Event.leave(room, account)

    case insert_single_event(room, state_set, leave_event) do
      {:ok, {state_set, room}} -> {:reply, :ok, %{state | state_set: state_set, room: room}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:kick, account, %Kick{user_id: user_id, reason: reason}},
        _from,
        %{room: room, state_set: state_set} = state
      ) do
    kick_event = Event.kick(room, account, user_id, reason)

    case insert_single_event(room, state_set, kick_event) do
      {:ok, {state_set, room}} -> {:reply, :ok, %{state | state_set: state_set, room: room}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @spec insert_single_event(Room.t(), t(), Event.t()) :: {:ok, t(), Room.t()} | {:error, atom()}
  defp insert_single_event(room, state_set, event) do
    Repo.transaction(fn ->
      case finalize_and_insert_event(event, state_set, room) do
        {:ok, state_set, room} ->
          _ = update_room_state_set(room, state_set)
          {state_set, room}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # Get a function that inserts all events for room creation.
  @spec create_room_insert_events(Room.t(), Account.t(), CreateRoom.t()) ::
          (() -> {:ok, t(), Room.t()} | {:error, atom()})
  defp create_room_insert_events(room, account, %CreateRoom{
         room_version: room_version,
         preset: preset,
         name: name,
         topic: topic
       }) do
    events =
      ([
         Event.create_room(room, account, room_version),
         Event.join(room, account),
         Event.power_levels(room, account)
       ] ++
         room_creation_preset(account, preset, room) ++
         [
           if(name, do: Event.name(room, account, name)),
           if(topic, do: Event.topic(room, account, topic))
         ])
      |> Enum.reject(&Kernel.is_nil/1)

    fn ->
      result =
        Enum.reduce_while(events, {%{}, room}, fn event, {state_set, room} ->
          case finalize_and_insert_event(event, state_set, room) do
            {:ok, state_set, room} -> {:cont, {state_set, room}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case result do
        {:error, reason} ->
          Repo.rollback(reason)

        {state_set, room} ->
          _ = update_room_state_set(room, state_set)
          {state_set, room}
      end
    end
  end

  # Update the given room in the database with the given state set.
  @spec update_room_state_set(Room.t(), t()) :: Room.t()
  defp update_room_state_set(room, state_set) do
    # TODO: We might as well hold state in the Room struct,
    #       instead of the state_set state.
    #       Create custom type for this.
    serialized_state_set =
      Enum.map(state_set, fn {{type, state_key}, event} ->
        [type, state_key, event.event_id]
      end)

    Repo.update!(change(room, state: serialized_state_set))
  end

  # Get the events for room creation as dictated by the given preset.
  # TODO: trusted_private_chat:
  #       All invitees are given the same power level as the room creator.
  @spec room_creation_preset(Account.t(), String.t() | nil, Room.t()) :: [Event.t()]
  defp room_creation_preset(account, nil, %Room{visibility: visibility} = room) do
    preset =
      case visibility do
        :public -> "public_chat"
        :private -> "private_chat"
      end

    room_creation_preset(account, preset, room)
  end

  defp room_creation_preset(account, preset, room) do
    {join_rule, his_vis, guest_access} =
      case preset do
        "private_chat" -> {"invite", "shared", "can_join"}
        "trusted_private_chat" -> {"invite", "shared", "can_join"}
        "public_chat" -> {"public", "shared", "forbidden"}
      end

    [
      Event.join_rules(room, account, join_rule),
      Event.history_visibility(room, account, his_vis),
      Event.guest_access(room, account, guest_access)
    ]
  end

  # Finalize the event struct and insert it into the room's state using state resolution.
  # The values that are automatically added are:
  # - Auth events
  # - Prev events
  # - Content hash
  # - Event ID
  # - Signature
  @spec finalize_and_insert_event(Event.t(), t(), Room.t()) ::
          {:ok, t(), Room.t()} | {:error, atom()}
  defp finalize_and_insert_event(
         event,
         state_set,
         %Room{forward_extremities: forward_extremities} = room
       ) do
    event =
      event
      |> Map.put(:auth_events, auth_events_for_event(event, state_set))
      |> Map.put(:prev_events, forward_extremities)

    case Event.post_process(event) do
      {:ok, event} -> authenticate_and_insert_event(event, state_set, room)
      _ -> {:error, :event_creation}
    end
  end

  # Get the auth events for an events.
  @spec auth_events_for_event(Event.t(), t()) :: [{String.t(), String.t()}]
  defp auth_events_for_event(%Event{type: "m.room.create"}, _), do: []

  defp auth_events_for_event(
         %Event{sender: sender} = event,
         state_set
       ) do
    state_pairs =
      [{"m.room.create", ""}, {"m.room.power_levels", ""}, {"m.room.member", to_string(sender)}] ++
        auth_events_for_member_event(event)

    state_set
    |> Map.take(state_pairs)
    |> Map.values()
    |> Enum.map(& &1.event_id)
  end

  # Get the auth events specific to m.room.member events.
  @spec auth_events_for_member_event(Event.t()) :: [{String.t(), String.t()}]
  defp auth_events_for_member_event(
         %Event{
           type: "m.room.member",
           state_key: state_key,
           content: %{"membership" => membership}
         } = event
       ) do
    [
      {"m.room.member", state_key},
      if(membership in ["join", "invite"], do: {"m.room.join_rules", ""}),
      third_party_invite_state_pair(event)
    ]
    |> Enum.reject(&Kernel.is_nil/1)
  end

  defp auth_events_for_member_event(_), do: []

  # Get the third party invite state pair for an event, if it exists.
  @spec third_party_invite_state_pair(Event.t()) :: {String.t(), String.t()} | nil
  defp third_party_invite_state_pair(%Event{
         content: %{
           "membership" => "invite",
           "third_party_invite" => %{"signed" => %{"token" => token}}
         }
       }) do
    {"m.room.third_party_invite", token}
  end

  defp third_party_invite_state_pair(_), do: nil

  # Authenticate and insert a new event using state resolution.
  # Implements the checks as described in the
  # [Matrix docs](https://matrix.org/docs/spec/server_server/latest#checks-performed-on-receipt-of-a-pdu).
  @spec authenticate_and_insert_event(Event.t(), t(), Room.t()) ::
          {:ok, t(), Room.t()} | {:error, atom()}
  defp authenticate_and_insert_event(event, current_state_set, room) do
    # TODO: Correctly handle soft fails.
    # Check the following things:
    # 1. TODO: Is a valid event, otherwise it is dropped.
    # 2. TODO: Passes signature checks, otherwise it is dropped.
    # 3. TODO: Passes hash checks, otherwise it is redacted before being processed further.
    # 4. Passes authorization rules based on the event's auth events, otherwise it is rejected.
    # 5. Passes authorization rules based on the state at the event, otherwise it is rejected.
    # 6. Passes authorization rules based on the current state of the room, otherwise it is "soft failed".
    with true <- Event.prevalidate(event),
         true <- Authorization.authorized_by_auth_events?(event),
         state_set <- StateResolution.resolve(event, false),
         true <- Authorization.authorized?(event, state_set),
         true <- Authorization.authorized?(event, current_state_set) do
      room = Room.update_forward_extremities(event, room)
      event = Repo.insert!(event)
      state_set = StateResolution.resolve_forward_extremities(event)
      _ = update_joined_rooms(room, state_set)

      {:ok, state_set, room}
    else
      _ -> {:error, :authorization}
    end
  end

  # Update local accounts' room membership if applicable.
  # TODO: Could be a background job.
  @spec update_joined_rooms(Room.t(), t()) :: JoinedRoom.t() | nil
  defp update_joined_rooms(%Room{id: room_id}, state_set) do
    server_name = MatrixServer.server_name()

    {joined, not_joined} =
      state_set
      |> Enum.filter(fn {{type, state_key}, _} ->
        type == "m.room.member" and MatrixServer.get_domain(state_key) == server_name
      end)
      |> Enum.split_with(fn {_, %Event{content: %{"membership" => membership}}} ->
        membership == "join"
      end)

    joined_assocs =
      Enum.map(joined, fn {{_, state_key}, _} ->
        %{localpart: MatrixServer.get_localpart(state_key), room_id: room_id}
      end)

    not_joined_localparts =
      Enum.map(not_joined, fn {{_, state_key}, _} -> MatrixServer.get_localpart(state_key) end)

    _ = Repo.insert_all(JoinedRoom, joined_assocs, on_conflict: :nothing)

    Repo.delete_all(
      from jr in JoinedRoom,
        where: jr.room_id == ^room_id and jr.localpart in ^not_joined_localparts
    )
  end
end
