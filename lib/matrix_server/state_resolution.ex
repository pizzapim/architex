defmodule MatrixServer.StateResolution do
  import Ecto.Query

  alias MatrixServer.{Repo, Event}

  def example do
    %Event{content: content} = event = Event.power_levels("room1", "charlie")
    event = %Event{event | content: %{content | "ban" => 0}}

    event
    |> Map.put(:prev_events, ["b", "fork"])
    |> Map.put(:auth_events, ["create", "join_charlie", "b"])
  end

  def resolve(%Event{room_id: room_id} = event, apply_state \\ false) do
    room_events =
      Event
      |> where([e], e.room_id == ^room_id)
      |> select([e], {e.event_id, e})
      |> Repo.all()
      |> Enum.into(%{})

    resolve(event, room_events, apply_state)
  end

  def resolve(
        %Event{type: type, state_key: state_key, event_id: event_id, prev_events: prev_event_ids},
        room_events,
        apply_state
      ) do
    state_sets =
      prev_event_ids
      |> Enum.map(&room_events[&1])
      |> Enum.map(&resolve(&1, room_events))

    resolved_state = do_resolve(state_sets, room_events)
    # TODO: check if state event
    if apply_state do
      Map.put(resolved_state, {type, state_key}, event_id)
    else
      resolved_state
    end
  end

  def do_resolve([], _), do: %{}

  def do_resolve(state_sets, room_events) do
    {unconflicted_state_map, conflicted_state_set} = calculate_conflict(state_sets)

    if MapSet.size(conflicted_state_set) == 0 do
      unconflicted_state_map
    else
      do_resolve(state_sets, room_events, unconflicted_state_map, conflicted_state_set)
    end
  end

  def do_resolve(state_sets, room_events, unconflicted_state_map, conflicted_state_set) do
    full_conflicted_set =
      MapSet.union(conflicted_state_set, auth_difference(state_sets, room_events))

    conflicted_control_event_ids =
      full_conflicted_set
      |> Enum.filter(&is_control_event(&1, room_events))
      |> MapSet.new()

    conflicted_control_events_with_auth_ids =
      conflicted_control_event_ids
      |> MapSet.to_list()
      |> full_auth_chain(room_events)
      |> MapSet.intersection(full_conflicted_set)
      |> MapSet.union(conflicted_control_event_ids)

    sorted_control_events =
      conflicted_control_events_with_auth_ids
      |> Enum.map(&room_events[&1])
      |> Enum.sort(rev_top_pow_order(room_events))

    partial_resolved_state =
      iterative_auth_checks(sorted_control_events, unconflicted_state_map, room_events)

    resolved_power_levels = partial_resolved_state[{"m.room.power_levels", ""}]

    conflicted_control_events_with_auth_ids
    |> MapSet.difference(full_conflicted_set)
    |> Enum.map(&room_events[&1])
    |> Enum.sort(mainline_order(resolved_power_levels, room_events))
    |> iterative_auth_checks(partial_resolved_state, room_events)
    |> Map.merge(unconflicted_state_map)
  end

  def calculate_conflict(state_sets) do
    {unconflicted, conflicted} =
      state_sets
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()
      |> Enum.into(%{}, fn state_pair ->
        events =
          Enum.map(state_sets, &Map.get(&1, state_pair))
          |> MapSet.new()

        {state_pair, events}
      end)
      |> Enum.split_with(fn {_, events} ->
        MapSet.size(events) == 1
      end)

    unconflicted_state_map =
      Enum.into(unconflicted, %{}, fn {state_pair, events} ->
        event = MapSet.to_list(events) |> hd()

        {state_pair, event}
      end)

    conflicted_state_set =
      Enum.reduce(conflicted, MapSet.new(), fn {_, events}, acc ->
        MapSet.union(acc, events)
      end)
      |> MapSet.delete(nil)

    {unconflicted_state_map, conflicted_state_set}
  end

  def auth_difference(state_sets, room_events) do
    # TODO: memoization possible
    full_auth_chains =
      Enum.map(state_sets, fn state_set ->
        state_set
        |> Map.values()
        |> full_auth_chain(room_events)
      end)

    auth_chain_union = Enum.reduce(full_auth_chains, MapSet.new(), &MapSet.union/2)
    auth_chain_intersection = Enum.reduce(full_auth_chains, MapSet.new(), &MapSet.intersection/2)

    MapSet.difference(auth_chain_union, auth_chain_intersection)
  end

  def full_auth_chain(event_ids, room_events) do
    event_ids
    |> Enum.map(&auth_chain(&1, room_events))
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  def auth_chain(event_id, room_events) do
    # TODO: handle when auth event is not found.
    room_events[event_id].auth_events
    |> Enum.reduce(MapSet.new(), fn auth_event_id, acc ->
      auth_event_id
      |> auth_chain(room_events)
      |> MapSet.union(acc)
      |> MapSet.put(auth_event_id)
    end)
  end

  def is_control_event(event_id, room_events), do: is_control_event(room_events[event_id])

  def is_control_event(%Event{type: "m.room.power_levels", state_key: ""}), do: true
  def is_control_event(%Event{type: "m.room.join_rules", state_key: ""}), do: true

  def is_control_event(%Event{
        type: "m.room.member",
        state_key: state_key,
        sender: sender,
        content: %{membership: membership}
      })
      when sender != state_key and membership in ["leave", "ban"],
      do: true

  def is_control_event(_), do: false

  def rev_top_pow_order(room_events) do
    fn %Event{origin_server_ts: timestamp1, event_id: event_id1} = event1,
       %Event{origin_server_ts: timestamp2, event_id: event_id2} = event2 ->
      power1 = get_power_level(event1, room_events)
      power2 = get_power_level(event2, room_events)

      if power1 == power2 do
        if timestamp1 == timestamp2 do
          event_id1 <= event_id2
        else
          timestamp1 < timestamp2
        end
      else
        power1 < power2
      end
    end
  end

  def get_power_level(%Event{sender: sender, auth_events: auth_event_ids}, room_events) do
    pl_event_id =
      Enum.find(auth_event_ids, fn id ->
        room_events[id].type == "m.room.power_levels"
      end)

    case room_events[pl_event_id] do
      %Event{content: %{"users" => pl_users}} -> Map.get(pl_users, sender, 0)
      nil -> 0
    end
  end

  def mainline_order(event_id, room_events) do
    mainline_map =
      room_events[event_id]
      |> mainline(room_events)
      |> Enum.with_index()
      |> Enum.into(%{})

    fn %Event{origin_server_ts: timestamp1, event_id: event_id1} = event1,
       %Event{origin_server_ts: timestamp2, event_id: event_id2} = event2 ->
      mainline_depth1 = get_mainline_depth(mainline_map, event1, room_events)
      mainline_depth2 = get_mainline_depth(mainline_map, event2, room_events)

      if mainline_depth1 == mainline_depth2 do
        if timestamp1 == timestamp2 do
          event_id1 <= event_id2
        else
          timestamp1 < timestamp2
        end
      else
        mainline_depth1 < mainline_depth2
      end
    end
  end

  defp get_mainline_depth(mainline_map, event, room_events) do
    mainline = mainline(event, room_events)

    result =
      Enum.find_value(mainline, fn mainline_event ->
        if Map.has_key?(mainline_map, mainline_event) do
          {:ok, mainline_map[mainline_event]}
        else
          nil
        end
      end)

    case result do
      {:ok, index} -> -index
      nil -> nil
    end
  end

  def mainline(event, room_events) do
    event
    |> mainline([], room_events)
    |> Enum.reverse()
  end

  def mainline(%Event{auth_events: auth_event_ids} = event, acc, room_events) do
    pl_event_id =
      Enum.find(auth_event_ids, fn id ->
        room_events[id].type == "m.room.power_levels"
      end)

    case room_events[pl_event_id] do
      %Event{} = pl_event -> mainline(pl_event, [event | acc], room_events)
      nil -> [event | acc]
    end
  end

  def iterative_auth_checks(events, state_set, room_events) do
    Enum.reduce(events, state_set, fn event, acc ->
      if is_authorized2(event, acc, room_events), do: update_state_set(event, acc), else: acc
    end)
  end

  def update_state_set(
        %Event{type: event_type, state_key: state_key, event_id: event_id},
        state_set
      ) do
    Map.put(state_set, {event_type, state_key}, event_id)
  end

  def is_authorized2(%Event{auth_events: auth_event_ids} = event, state_set, room_events) do
    state_set =
      auth_event_ids
      |> Enum.map(&room_events[&1])
      |> Enum.reduce(state_set, fn %Event{
                                     type: event_type,
                                     state_key: state_key,
                                     event_id: event_id
                                   },
                                   acc ->
        Map.put_new(acc, {event_type, state_key}, event_id)
      end)

    is_authorized(event, state_set, room_events)
  end

  # TODO: join and power levels events
  def is_authorized(%Event{type: "m.room.create", prev_events: prev_events}, _, _),
    do: prev_events == []

  def is_authorized(
        %Event{type: "m.room.member", content: %{"membership" => "join"}, state_key: user},
        state_set,
        room_events
      ) do
    allowed_to_join(user, state_set, room_events)
  end

  def is_authorized(%Event{sender: sender} = event, state_set, room_events) do
    in_room(sender, state_set, room_events) and
      has_power_level(
        sender,
        get_power_levels(state_set, room_events),
        get_event_power_level(event)
      )
  end

  def in_room(user, state_set, room_events) when is_map_key(state_set, {"m.room.member", user}) do
    event_id = state_set[{"m.room.member", user}]

    case room_events[event_id].content["membership"] do
      "join" -> true
      _ -> false
    end
  end

  def in_room(_, _, _), do: false

  def get_power_levels(state_set, room_events)
      when is_map_key(state_set, {"m.room.power_levels", ""}) do
    event_id = state_set[{"m.room.power_levels", ""}]
    room_events[event_id].content
  end

  def get_power_levels(_, _), do: nil

  def has_power_level(user, %{"users" => users}, level) do
    Map.get(users, user, 0) >= level
  end

  def has_power_level(_, _, _) do
    true
  end

  defp get_event_power_level(%Event{state_key: ""}), do: 0
  defp get_event_power_level(_), do: 50

  # No join rules specified, allow joining for room creator only.
  def allowed_to_join(user, state_set, room_events)
      when not is_map_key(state_set, {"m.room.join_rules", ""}) do
    event_id = state_set[{"m.room.create", ""}]
    room_events[event_id].sender == user
  end
end
