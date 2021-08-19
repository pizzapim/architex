defmodule MatrixServer.StateResolution do
  import Ecto.Query

  alias MatrixServer.{Repo, Event, Room}
  alias MatrixServer.StateResolution.Authorization

  @type state_set :: map()

  def resolve(event), do: resolve(event, true)

  def resolve(%Event{room_id: room_id} = event, apply_state) do
    room_events =
      Event
      |> where([e], e.room_id == ^room_id)
      |> select([e], {e.event_id, e})
      |> Repo.all()
      |> Enum.into(%{})

    resolve(event, room_events, apply_state)
  end

  def resolve(
        %Event{type: type, state_key: state_key, prev_events: prev_event_ids} = event,
        room_events,
        apply_state
      ) do
    state_sets =
      prev_event_ids
      |> Enum.map(&room_events[&1])
      |> Enum.map(&resolve(&1, room_events, true))

    resolved_state = do_resolve(state_sets, room_events)

    if apply_state and Event.is_state_event(event) do
      Map.put(resolved_state, {type, state_key}, event)
    else
      resolved_state
    end
  end

  def resolve_forward_extremities(%Event{room_id: room_id}) do
    room_events =
      Event
      |> where([e], e.room_id == ^room_id)
      |> select([e], {e.event_id, e})
      |> Repo.all()
      |> Enum.into(%{})

    Event
    |> where([e], e.room_id == ^room_id)
    |> join(:inner, [e], r in Room, on: e.room_id == r.id)
    |> where([e, r], e.event_id == fragment("ANY(?)", r.forward_extremities))
    |> Repo.all()
    |> Enum.map(&resolve/1)
    |> do_resolve(room_events)
  end

  defp do_resolve([], _), do: %{}

  defp do_resolve(state_sets, room_events) do
    {unconflicted_state_map, conflicted_state_set} = calculate_conflict(state_sets, room_events)

    if MapSet.size(conflicted_state_set) == 0 do
      unconflicted_state_map
    else
      do_resolve(state_sets, room_events, unconflicted_state_map, conflicted_state_set)
    end
  end

  defp do_resolve(state_sets, room_events, unconflicted_state_map, conflicted_state_set) do
    full_conflicted_set =
      MapSet.union(conflicted_state_set, auth_difference(state_sets, room_events))

    conflicted_control_event_ids =
      full_conflicted_set
      |> Enum.filter(&Event.is_control_event(room_events[&1]))
      |> MapSet.new()

    conflicted_control_events_with_auth_ids =
      conflicted_control_event_ids
      |> Enum.map(&room_events[&1])
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
    |> Enum.sort(mainline_order(resolved_power_levels, room_events))
    |> Enum.map(&room_events[&1])
    |> iterative_auth_checks(partial_resolved_state, room_events)
    |> Map.merge(unconflicted_state_map)
  end

  defp calculate_conflict(state_sets, room_events) do
    {unconflicted, conflicted} =
      state_sets
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()
      |> Enum.into(%{}, fn state_pair ->
        events =
          Enum.map(state_sets, fn
            state_set when is_map_key(state_set, state_pair) -> state_set[state_pair].event_id
            _ -> nil
          end)
          |> MapSet.new()

        {state_pair, events}
      end)
      |> Enum.split_with(fn {_, event_ids} ->
        MapSet.size(event_ids) == 1
      end)

    unconflicted_state_map =
      Enum.into(unconflicted, %{}, fn {state_pair, event_ids} ->
        event_id = MapSet.to_list(event_ids) |> hd()

        {state_pair, room_events[event_id]}
      end)

    conflicted_state_set =
      Enum.reduce(conflicted, MapSet.new(), fn {_, events}, acc ->
        MapSet.union(acc, events)
      end)
      |> MapSet.delete(nil)

    {unconflicted_state_map, conflicted_state_set}
  end

  defp auth_difference(state_sets, room_events) do
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

  defp full_auth_chain(events, room_events) do
    events
    |> Enum.map(&auth_chain(&1, room_events))
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp auth_chain(%Event{auth_events: auth_events}, room_events) do
    auth_events
    |> Enum.map(&room_events[&1])
    |> Enum.reduce(MapSet.new(), fn %Event{event_id: auth_event_id} = auth_event, acc ->
      auth_event
      |> auth_chain(room_events)
      |> MapSet.union(acc)
      |> MapSet.put(auth_event_id)
    end)
  end

  defp rev_top_pow_order(room_events) do
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

  defp get_power_level(%Event{sender: sender, auth_events: auth_event_ids}, room_events) do
    pl_event_id =
      Enum.find(auth_event_ids, fn id ->
        room_events[id].type == "m.room.power_levels"
      end)

    # TODO: refactor
    case room_events[pl_event_id] do
      %Event{content: %{"users" => pl_users}} -> Map.get(pl_users, to_string(sender), 0)
      nil -> 0
    end
  end

  defp mainline_order(event, room_events) do
    mainline_map =
      event
      |> mainline(room_events)
      |> Enum.with_index()
      |> Enum.into(%{})

    fn event_id1, event_id2 ->
      %Event{origin_server_ts: timestamp1} = event1 = room_events[event_id1]
      %Event{origin_server_ts: timestamp2} = event2 = room_events[event_id2]
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

  defp mainline(event, room_events) do
    event
    |> mainline([], room_events)
    |> Enum.reverse()
  end

  defp mainline(%Event{auth_events: auth_event_ids} = event, acc, room_events) do
    pl_event_id =
      Enum.find(auth_event_ids, fn id ->
        room_events[id].type == "m.room.power_levels"
      end)

    case room_events[pl_event_id] do
      %Event{} = pl_event -> mainline(pl_event, [event | acc], room_events)
      nil -> [event | acc]
    end
  end

  defp iterative_auth_checks(events, state_set, room_events) do
    Enum.reduce(events, state_set, fn event, acc ->
      if authorized?(event, acc, room_events), do: update_state_set(event, acc), else: acc
    end)
  end

  def update_state_set(
        %Event{type: event_type, state_key: state_key} = event,
        state_set
      ) do
    Map.put(state_set, {event_type, state_key}, event)
  end

  defp authorized?(%Event{auth_events: auth_event_ids} = event, state_set, room_events) do
    state_set =
      auth_event_ids
      |> Enum.map(&room_events[&1])
      |> Enum.reduce(state_set, &update_state_set/2)

    Authorization.authorized?(event, state_set)
  end
end
