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

  def resolve(%Event{type: type, state_key: state_key, event_id: event_id, prev_events: prev_event_ids}) do
    state_sets = Event
      |> where([e], e.event_id in ^prev_event_ids)
      |> Repo.all()
      |> Enum.map(&resolve/1)
    
    resolved_state = resolve(state_sets)
    # TODO: check if state event
    Map.put(resolved_state, {type, state_key}, event_id)
  end

  def resolve([]), do: %{}

  def resolve(state_sets) do
    {unconflicted_state_map, conflicted_state_set} = calculate_conflict(state_sets)
    if MapSet.size(conflicted_state_set) == 0 do
      unconflicted_state_map
    else
      full_conflicted_set = MapSet.union(conflicted_state_set, auth_difference(state_sets))

      conflicted_control_event_ids =
        Enum.filter(full_conflicted_set, &is_control_event/1) |> MapSet.new()

      conflicted_control_event_ids_with_auth =
        conflicted_control_event_ids
        |> MapSet.to_list()
        |> full_auth_chain()
        |> MapSet.intersection(full_conflicted_set)
        |> MapSet.union(conflicted_control_event_ids)

      conflicted_control_events_with_auth =
        Repo.all(
          from e in Event,
            where: e.event_id in ^MapSet.to_list(conflicted_control_event_ids_with_auth)
        )

      sorted_control_events = Enum.sort(conflicted_control_events_with_auth, &rev_top_pow_order/2)

      partial_resolved_state = iterative_auth_checks(sorted_control_events, unconflicted_state_map)

      other_conflicted_event_ids =
        MapSet.difference(full_conflicted_set, conflicted_control_event_ids_with_auth)

      other_conflicted_events =
        Repo.all(from e in Event, where: e.event_id in ^MapSet.to_list(other_conflicted_event_ids))

      resolved_power_levels = partial_resolved_state[{"m.room.power_levels", ""}]

      sorted_other_events =
        Enum.sort(other_conflicted_events, mainline_order(resolved_power_levels))

      nearly_final_state = iterative_auth_checks(sorted_other_events, partial_resolved_state)

      Map.merge(nearly_final_state, unconflicted_state_map)
    end
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

  def auth_difference(state_sets) do
    # TODO: memoization possible
    full_auth_chains =
      Enum.map(state_sets, fn state_set ->
        state_set
        |> Map.values()
        |> full_auth_chain()
      end)

    auth_chain_union = Enum.reduce(full_auth_chains, MapSet.new(), &MapSet.union/2)
    auth_chain_intersection = Enum.reduce(full_auth_chains, MapSet.new(), &MapSet.intersection/2)

    MapSet.difference(auth_chain_union, auth_chain_intersection)
  end

  def full_auth_chain(event_ids) do
    event_ids
    |> Enum.map(&auth_chain/1)
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  def auth_chain(event_id) do
    # TODO: handle when auth event is not found.
    Event
    |> where([e], e.event_id == ^event_id)
    |> select([e], e.auth_events)
    |> Repo.one!()
    |> Enum.reduce(MapSet.new(), fn auth_event_id, acc ->
      auth_event_id
      |> auth_chain()
      |> MapSet.union(acc)
      |> MapSet.put(auth_event_id)
    end)
  end

  def is_control_event(event_id) when is_binary(event_id) do
    Event
    |> where([e], e.event_id == ^event_id)
    |> Repo.one!()
    |> is_control_event()
  end

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

  def rev_top_pow_order(
        %Event{origin_server_ts: timestamp1, event_id: event_id1} = event1,
        %Event{origin_server_ts: timestamp2, event_id: event_id2} = event2
      ) do
    {power1, power2} = {get_power_level(event1), get_power_level(event2)}

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

  def get_power_level(%Event{sender: sender, auth_events: auth_event_ids}) do
    pl_content =
      Event
      |> where([e], e.event_id in ^auth_event_ids)
      |> where([e], e.type == "m.room.power_levels")
      |> select([e], e.content)
      |> Repo.one()

    case pl_content do
      %{"users" => pl_users} -> Map.get(pl_users, sender, 0)
      nil -> 0
    end
  end

  def mainline_order(event_id) do
    mainline_map =
      Event
      |> where([e], e.event_id == ^event_id)
      |> Repo.one!()
      |> mainline()
      |> Enum.with_index()
      |> Enum.into(%{})

    fn %Event{origin_server_ts: timestamp1, event_id: event_id1} = event1,
       %Event{origin_server_ts: timestamp2, event_id: event_id2} = event2 ->
      mainline_depth1 = get_mainline_depth(mainline_map, event1)
      mainline_depth2 = get_mainline_depth(mainline_map, event2)

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

  defp get_mainline_depth(mainline_map, event) do
    mainline = mainline(event)

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

  def mainline(event) do
    event
    |> mainline([])
    |> Enum.reverse()
  end

  def mainline(%Event{auth_events: auth_event_ids} = event, acc) do
    pl_event =
      Event
      |> where([e], e.event_id in ^auth_event_ids)
      |> where([e], e.type == "m.room.power_levels")
      |> Repo.one()

    case pl_event do
      %Event{} -> mainline(pl_event, [event | acc])
      nil -> [event | acc]
    end
  end

  def iterative_auth_checks(events, state_set) do
    Enum.reduce(events, state_set, fn event, acc ->
      if is_authorized2(event, acc), do: insert_event(event, acc), else: acc
    end)
  end

  def insert_event(%Event{type: event_type, state_key: state_key, event_id: event_id}, state_set) do
    Map.put(state_set, {event_type, state_key}, event_id)
  end

  def is_authorized2(%Event{auth_events: auth_event_ids} = event, state_set) do
    state_set =
      Event
      |> where([e], e.event_id in ^auth_event_ids)
      |> Repo.all()
      |> Enum.reduce(state_set, fn %Event{
                                     type: event_type,
                                     state_key: state_key,
                                     event_id: event_id
                                   },
                                   acc ->
        Map.put_new(acc, {event_type, state_key}, event_id)
      end)

    is_authorized(event, state_set)
  end

  # TODO: join and power levels events
  def is_authorized(%Event{type: "m.room.create", prev_events: prev_events}, _),
    do: prev_events == []

  def is_authorized(
        %Event{type: "m.room.member", content: %{"membership" => "join"}, state_key: user},
        state_set
      ) do
    allowed_to_join(user, state_set)
  end

  def is_authorized(%Event{sender: sender} = event, state_set) do
    in_room(sender, state_set) and
      has_power_level(sender, get_power_levels(state_set), get_event_power_level(event))
  end

  def in_room(user, state_set) when is_map_key(state_set, {"m.room.member", user}) do
    content =
      Repo.one!(
        from e in Event,
          where: e.event_id == ^state_set[{"m.room.member", user}],
          select: e.content
      )

    case content["membership"] do
      "join" -> true
      _ -> false
    end
  end

  def in_room(_, _), do: false

  def get_power_levels(state_set) when is_map_key(state_set, {"m.room.power_levels", ""}) do
    Repo.one!(
      from e in Event,
        where: e.event_id == ^state_set[{"m.room.power_levels", ""}],
        select: e.content
    )
  end

  def get_power_levels(_), do: nil

  def has_power_level(user, %{"users" => users}, level) do
    Map.get(users, user, 0) >= level
  end

  def has_power_level(_, _, _) do
    true
  end

  defp get_event_power_level(%Event{state_key: ""}), do: 0
  defp get_event_power_level(_), do: 50

  # No join rules specified, allow joining for room creator only.
  def allowed_to_join(user, state_set)
      when not is_map_key(state_set, {"m.room.join_rules", ""}) do
    Repo.one!(
      from e in Event, where: e.event_id == ^state_set[{"m.room.create", ""}], select: e.sender
    ) == user
  end
end
