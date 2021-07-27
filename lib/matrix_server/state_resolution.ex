defmodule MatrixServer.StateResolution do
  import Ecto.Query

  alias MatrixServer.{Repo, Event, Room}

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

  def is_authorized_by_auth_events(%Event{auth_events: auth_event_ids} = event) do
    # We assume the auth events are validated beforehand.
    state_set =
      Event
      |> where([e], e.event_id in ^auth_event_ids)
      |> Repo.all()
      |> Enum.reduce(%{}, &update_state_set/2)

    is_authorized(event, state_set)
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

  def is_authorized(%Event{type: "m.room.create", prev_events: prev_events}, %{}),
    do: prev_events == []

  # Check rule: 5.2.1
  def is_authorized(%Event{type: "m.room.member", state_key: state_key}, %{
        {"m.room.create", ""} => %Event{content: %{"creator" => creator}}
      }),
      do: state_key == creator

  def is_authorized(
        %Event{type: "m.room.member", sender: sender, content: %{"membership" => "join"}},
        state_set
      ) do
    join_rule = get_join_rule(state_set)
    membership = get_membership(sender, state_set)

    # Check rules: 5.2.3, 5.2.4, 5.2.5
    cond do
      membership == "ban" -> false
      join_rule == "invite" -> membership in ["invite", "join"]
      join_rule == "public" -> true
      true -> false
    end
  end

  # TODO: rule 5.3.1
  def is_authorized(
        %Event{
          type: "m.room.member",
          content: %{"membership" => "invite", "third_party_invite" => _}
        },
        _
      ),
      do: false

  def is_authorized(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "invite"},
          state_key: state_key
        },
        state_set
      ) do
    sender_membership = get_membership(sender, state_set)
    target_membership = get_membership(state_key, state_set)
    power_levels = get_power_levels(state_set)

    # Check rules: 5.3.2, 5.3.3, 5.3.4
    cond do
      sender_membership != "join" -> false
      target_membership in ["join", "ban"] -> false
      has_power_level(sender, power_levels, :invite) -> true
      true -> false
    end
  end

  def is_authorized(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "leave"},
          state_key: sender
        },
        state_set
      ) do
    # Check rule: 5.4.1
    get_membership(sender, state_set) in ["invite", "join"]
  end

  def is_authorized(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "leave"},
          state_key: state_key
        },
        state_set
      ) do
    sender_membership = get_membership(sender, state_set)
    target_membership = get_membership(state_key, state_set)
    power_levels = get_power_levels(state_set)
    sender_pl = get_user_power_level(sender, power_levels)
    target_pl = get_user_power_level(state_key, power_levels)

    # Check rules: 5.4.2, 5.4.3, 5.4.4
    cond do
      sender_membership != "join" -> false
      target_membership == "ban" and not has_power_level(sender, power_levels, :ban) -> false
      has_power_level(sender, power_levels, :kick) and target_pl < sender_pl -> true
      true -> false
    end
  end

  def is_authorized(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "ban"},
          state_key: state_key
        },
        state_set
      ) do
    sender_membership = get_membership(sender, state_set)
    power_levels = get_power_levels(state_set)
    sender_pl = get_user_power_level(sender, power_levels)
    target_pl = get_user_power_level(state_key, power_levels)

    # Check rules: 5.5.1, 5.5.2
    cond do
      sender_membership != "join" -> false
      has_power_level(sender, power_levels, :ban) and target_pl < sender_pl -> true
      true -> false
    end
  end

  # Check rule: 5.6
  def is_authorized(%Event{type: "m.room.member"}, _), do: false

  def is_authorized(%Event{sender: sender} = event, state_set) do
    # Check rule: 6
    get_membership(sender, state_set) == "join" and _is_authorized(event, state_set)
  end

  defp _is_authorized(%Event{type: "m.room.third_party_invite", sender: sender}, state_set) do
    # Check rule: 7.1
    has_power_level(sender, state_set, :invite)
  end

  defp _is_authorized(%Event{state_key: state_key, sender: sender} = event, state_set) do
    power_levels = get_power_levels(state_set)

    # Check rules: 8, 9
    cond do
      not has_power_level(sender, power_levels, {:event, event}) -> false
      String.starts_with?(state_key, "@") and state_key != sender -> false
      true -> __is_authorized(event, state_set)
    end
  end

  defp __is_authorized(
         %Event{type: "m.room.power_levels", sender: sender, content: content},
         state_set
       ) do
    current_pls = get_power_levels(state_set)
    new_pls = content
    sender_pl = get_user_power_level(sender, new_pls)

    # Check rules: 10.2, 10.3, 10.4, 10.5
    cond do
      not is_map_key(state_set, {"m.room.power_levels", ""}) -> true
      not authorize_power_levels(sender, sender_pl, current_pls, new_pls) -> false
      true -> true
    end
  end

  # TODO: Rule 11

  defp __is_authorized(_, _), do: true

  defp authorize_power_levels(
         user,
         user_pl,
         %{"events" => current_events, "users" => current_users} = current_pls,
         %{"events" => new_events, "users" => new_users} = new_pls
       ) do
    keys = ["users_default", "events_default", "state_default", "ban", "redact", "kick", "invite"]

    valid_power_level_key_changes(Map.take(current_pls, keys), Map.take(new_pls, keys), user_pl) and
      valid_power_level_key_changes(current_events, new_events, user_pl) and
      valid_power_level_key_changes(current_users, new_users, user_pl) and
      valid_power_level_users_changes(current_users, new_users, user, user_pl)
  end

  defp has_power_level(user, power_levels, action) do
    user_pl = get_user_power_level(user, power_levels)
    action_pl = get_action_power_level(action, power_levels)

    user_pl >= action_pl
  end

  defp get_user_power_level(user, %{"users" => users}) when is_map_key(users, user),
    do: users[user]

  defp get_user_power_level(_, %{"users_default" => pl}), do: pl
  defp get_user_power_level(_, _), do: 0

  defp get_action_power_level(:invite, %{"invite" => pl}), do: pl
  defp get_action_power_level(:invite, _), do: 50
  defp get_action_power_level(:ban, %{"ban" => pl}), do: pl
  defp get_action_power_level(:ban, _), do: 50
  defp get_action_power_level(:redact, %{"redact" => pl}), do: pl
  defp get_action_power_level(:redact, _), do: 50

  defp get_action_power_level({:event, %Event{type: type}}, %{"events" => events})
       when is_map_key(events, type),
       do: events[type]

  defp get_action_power_level({:event, event}, power_levels) do
    if Event.is_state_event(event) do
      case power_levels do
        %{"state_default" => pl} -> pl
        %{} -> 50
        _ -> 0
      end
    else
      case power_levels do
        %{"events_default" => pl} -> pl
        _ -> 0
      end
    end
  end

  defp get_power_levels(state_set) do
    case state_set[{"m.room.power_levels", ""}] do
      %Event{content: content} -> content
      nil -> nil
    end
  end

  defp get_join_rule(state_set) do
    case state_set[{"m.room.join_rules", ""}] do
      %Event{content: %{"join_rule" => join_rule}} -> join_rule
      nil -> nil
    end
  end

  defp get_membership(user, state_set) do
    case state_set[{"m.room.member", user}] do
      %Event{content: %{"membership" => membership}} -> membership
      nil -> nil
    end
  end

  defp valid_power_level_key_changes(l1, l2, user_pl) do
    set1 = MapSet.new(l1)
    set2 = MapSet.new(l2)

    MapSet.difference(
      MapSet.union(set1, set2),
      MapSet.intersection(set1, set2)
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.all?(fn {_k, values} ->
      Enum.all?(values, &(&1 <= user_pl))
    end)
  end

  defp valid_power_level_users_changes(current_users, new_users, user, user_pl) do
    set1 = MapSet.new(current_users)
    set2 = MapSet.new(new_users)

    MapSet.difference(
      MapSet.union(set1, set2),
      MapSet.intersection(set1, set2)
    )
    |> Enum.all?(fn
      {_k, values} when length(values) != 2 -> true
      {k, _} when k == user -> true
      {_k, [old_value, _]} -> old_value != user_pl
    end)
  end

  def testing do
    %Event{content: content} = event = Event.power_levels("room1", "charlie")
    event = %Event{event | content: %{content | "ban" => 0}}

    event
    |> Map.put(:prev_events, ["b", "fork"])
    |> Map.put(:auth_events, ["create", "join_charlie", "b"])
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
      %Event{content: %{"users" => pl_users}} -> Map.get(pl_users, sender, 0)
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
      if is_authorized2(event, acc, room_events), do: update_state_set(event, acc), else: acc
    end)
  end

  defp update_state_set(
         %Event{type: event_type, state_key: state_key} = event,
         state_set
       ) do
    Map.put(state_set, {event_type, state_key}, event)
  end

  defp is_authorized2(%Event{auth_events: auth_event_ids} = event, state_set, room_events) do
    state_set =
      auth_event_ids
      |> Enum.map(&room_events[&1])
      |> Enum.reduce(state_set, &update_state_set/2)

    is_authorized(event, state_set)
  end
end
