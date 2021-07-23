# https://matrix.uhoreg.ca/stateres/reloaded.html
defmodule MatrixServer.StateResolutionExample do
  @derive {Inspect, except: [:prev_events, :auth_events]}
  defstruct [
    :event_id,
    :event_type,
    :timestamp,
    :state_key,
    :sender,
    :content,
    :prev_events,
    :auth_events,
    :power_levels
  ]

  alias __MODULE__, as: Event

  @type t :: %Event{event_id: String.t(), event_type: Atom.t(), timestamp: Integer.t()}

  def new_state_event, do: %Event{new() | event_type: :state}
  def new_message_event, do: %Event{new() | event_type: :message}

  # TODO: remove state_key default here
  def new do
    %Event{
      event_id: "",
      timestamp: 0,
      state_key: "",
      sender: "",
      content: "",
      prev_events: [],
      auth_events: [],
      power_levels: %{}
    }
  end

  def join(user), do: %Event{membership(user) | content: "join"}
  def leave(user), do: %Event{membership(user) | content: "leave"}
  def invite(actor, subject), do: %Event{membership(actor, subject) | content: "invite"}
  def kick(actor, subject), do: %Event{membership(actor, subject) | content: "leave"}
  def ban(actor, subject), do: %Event{membership(actor, subject) | content: "ban"}

  def set_power_levels(user, power_levels) do
    %Event{new() | event_type: :power_levels, sender: user, power_levels: power_levels}
  end

  def set_topic(user, topic) do
    %Event{new() | event_type: :topic, sender: user, content: topic}
  end

  def get_state_set_from_event_list(events) do
    Enum.reduce(events, %{}, fn
      %Event{event_type: event_type, state_key: state_key} = event, acc ->
        Map.put(acc, {event_type, state_key}, event)
    end)
  end

  def auth_chain(event), do: auth_chain(event, MapSet.new())

  def auth_chain(%Event{auth_events: auth_events}, set) do
    Enum.reduce(auth_events, set, fn event, acc ->
      event
      |> auth_chain()
      |> MapSet.union(acc)
      |> MapSet.put(event)
    end)
  end

  def in_room(user, state_set) when is_map_key(state_set, {:membership, user}) do
    state_set[{:membership, user}].content == "join"
  end

  def in_room(_, _), do: false

  def get_power_levels(state_set) when is_map_key(state_set, {:power_levels, ""}) do
    state_set[{:power_levels, ""}].power_levels
  end

  def get_power_levels(_), do: nil

  def has_power_level(_, nil, _), do: true

  def has_power_level(user, power_levels, level) do
    Map.get(power_levels, user, 0) >= level
  end

  # No join rules specified, allow joining for room creator only.
  def allowed_to_join(user, state_set) when not is_map_key(state_set, {:join_rules, ""}) do
    state_set[{:create, ""}].sender == user
  end

  # TODO: join and power levels events
  def is_authorized(%Event{event_type: :create, prev_events: prev_events}, _),
    do: prev_events == []

  def is_authorized(%Event{event_type: :membership, content: "join", state_key: user}, state_set) do
    allowed_to_join(user, state_set)
  end

  def is_authorized(%Event{sender: sender} = event, state_set) do
    in_room(sender, state_set) and
      has_power_level(sender, get_power_levels(state_set), get_event_power_level(event))
  end

  def is_authorized2(%Event{auth_events: auth_events} = event, state_set) do
    state_set =
      Enum.reduce(auth_events, state_set, fn %Event{event_type: event_type, state_key: state_key} =
                                               event,
                                             acc ->
        Map.put_new(acc, {event_type, state_key}, event)
      end)

    is_authorized(event, state_set)
  end

  def iterative_auth_checks(events, state_set) do
    Enum.reduce(events, state_set, fn event, acc ->
      if is_authorized2(event, acc), do: insert_event(event, acc), else: acc
    end)
  end

  def insert_event(%Event{event_type: event_type, state_key: state_key} = event, state_set) do
    Map.put(state_set, {event_type, state_key}, event)
  end

  def is_control_event(%Event{event_type: :power_levels, state_key: ""}), do: true

  def is_control_event(%Event{event_type: :join_rules, state_key: ""}), do: true

  def is_control_event(%Event{
        event_type: :membership,
        state_key: state_key,
        sender: sender,
        content: "ban"
      }),
      do: sender != state_key

  def is_control_event(%Event{
        event_type: :membership,
        state_key: state_key,
        sender: sender,
        content: "leave"
      }),
      do: sender != state_key

  def is_control_event(_), do: false

  def calculate_conflict(state_sets) do
    domain =
      state_sets
      |> Enum.map(&Map.keys/1)
      |> List.flatten()
      |> MapSet.new()

    full_state_map_list =
      Enum.map(domain, fn k ->
        events =
          Enum.map(state_sets, &Map.get(&1, k))
          |> MapSet.new()

        {k, events}
      end)

    {unconflicted, conflicted} =
      Enum.split_with(full_state_map_list, fn {_k, events} ->
        MapSet.size(events) == 1
      end)

    unconflicted_state_map =
      Enum.map(unconflicted, fn {k, events} ->
        event =
          events
          |> MapSet.to_list()
          |> hd()

        {k, event}
      end)
      |> Enum.into(%{})

    conflicted_state_map =
      Enum.flat_map(conflicted, fn {_, events} ->
        events
        |> MapSet.delete(nil)
        |> MapSet.to_list()
      end)
      |> MapSet.new()

    {unconflicted_state_map, conflicted_state_map}
  end

  def full_auth_chain(events) do
    events
    |> Enum.map(&auth_chain/1)
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  def auth_difference(state_sets) do
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

  def rev_top_pow_order(
        %Event{timestamp: timestamp1, event_id: event_id1} = event1,
        %Event{timestamp: timestamp2, event_id: event_id2} = event2
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

  def get_power_level(%Event{sender: sender, auth_events: auth_events}) do
    pl_event = Enum.find(auth_events, &(&1.event_type == :power_levels))

    case pl_event do
      %Event{power_levels: power_levels} -> Map.get(power_levels, sender, 0)
      _ -> 0
    end
  end

  def mainline(event) do
    event
    |> mainline([])
    |> Enum.reverse()
  end

  def mainline(%Event{auth_events: auth_events} = event, acc) do
    case Enum.find(auth_events, &(&1.event_type == :power_levels)) do
      nil -> [event | acc]
      pl_event -> mainline(pl_event, [event | acc])
    end
  end

  def mainline_order(p) do
    mainline_map =
      p
      |> mainline()
      |> Enum.with_index()
      |> Enum.into(%{})

    fn %Event{timestamp: timestamp1, event_id: event_id1} = event1,
       %Event{timestamp: timestamp2, event_id: event_id2} = event2 ->
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

  def resolve(state_sets) do
    {unconflicted_state_map, conflicted_set} = calculate_conflict(state_sets)
    full_conflicted_set = MapSet.union(conflicted_set, auth_difference(state_sets))

    conflicted_control_events =
      Enum.filter(full_conflicted_set, &is_control_event/1) |> MapSet.new()

    conflicted_control_events_with_auth =
      MapSet.union(
        conflicted_control_events,
        MapSet.intersection(
          full_conflicted_set,
          full_auth_chain(MapSet.to_list(conflicted_control_events))
        )
      )

    sorted_control_events = Enum.sort(conflicted_control_events_with_auth, &rev_top_pow_order/2)
    partial_resolved_state = iterative_auth_checks(sorted_control_events, unconflicted_state_map)

    other_conflicted_events =
      MapSet.difference(full_conflicted_set, conflicted_control_events_with_auth)

    resolved_power_levels = partial_resolved_state[{:power_levels, ""}]

    sorted_other_events =
      Enum.sort(other_conflicted_events, mainline_order(resolved_power_levels))

    nearly_final_state = iterative_auth_checks(sorted_other_events, partial_resolved_state)

    Map.merge(nearly_final_state, unconflicted_state_map)
  end

  def example1 do
    create = %Event{new() | event_id: "create", event_type: :create, sender: "@alice:example.com"}

    alice_joins = %Event{
      join("@alice:example.com")
      | event_id: "alice joins",
        prev_events: [create],
        auth_events: [create]
    }

    pl = %Event{
      set_power_levels("@alice:example.com", %{"@alice:example.com" => 100})
      | event_id: "power level",
        prev_events: [alice_joins],
        auth_events: [alice_joins, create]
    }

    join_rules = %Event{
      new()
      | event_id: "join rules",
        event_type: :join_rules,
        sender: "@alice:example.com",
        content: "private",
        prev_events: [pl],
        auth_events: [pl, alice_joins, create]
    }

    invite_bob = %Event{
      invite("@alice:example.com", "@bob:example.com")
      | event_id: "invite bob",
        prev_events: [join_rules],
        auth_events: [pl, alice_joins, create]
    }

    invite_carol = %Event{
      invite("@alice:example.com", "@carol:example.com")
      | event_id: "invite carol",
        prev_events: [invite_bob],
        auth_events: [pl, alice_joins, create]
    }

    bob_join = %Event{
      join("@bob:example.com")
      | event_id: "bob joins",
        prev_events: [invite_carol],
        auth_events: [invite_bob, join_rules, create]
    }

    [create, alice_joins, pl, join_rules, invite_bob, invite_carol, bob_join]
  end

  def example2 do
    create = %Event{
      new_state_event()
      | event_id: "create",
        event_type: :create,
        sender: "@alice:example.com"
    }

    alice_joins = join("@alice:example.com")

    pl1 = %Event{
      set_power_levels("@alice:example.com", %{"@alice:example.com" => 100})
      | event_id: "power levels 1"
    }

    pl2 = %Event{
      set_power_levels("@alice:example.com", %{
        "@alice:example.com" => 100,
        "@bob:example.com" => 50
      })
      | event_id: "power levels 2"
    }

    topic = %Event{set_topic("@alice:example.com", "This is a topic") | event_id: "topic"}

    state_set1 = get_state_set_from_event_list([create, alice_joins, pl1])
    state_set2 = get_state_set_from_event_list([create, alice_joins, pl2, topic])
    state_set3 = get_state_set_from_event_list([create, alice_joins, pl2])
    [state_set1, state_set2, state_set3]
  end

  def example3 do
    pl1 = %Event{set_power_levels("alice", %{}) | event_id: "pl1", timestamp: 1}

    pl2 = %Event{
      set_power_levels("alice", %{})
      | event_id: "pl2",
        auth_events: [pl1],
        timestamp: 2
    }

    pl3 = %Event{
      set_power_levels("alice", %{})
      | event_id: "pl3",
        auth_events: [pl1],
        timestamp: 4
    }

    pl4 = %Event{
      set_power_levels("alice", %{})
      | event_id: "pl4",
        auth_events: [pl2],
        timestamp: 6
    }

    pl5 = %Event{
      set_power_levels("alice", %{})
      | event_id: "pl5",
        auth_events: [pl4],
        timestamp: 6
    }

    pl6 = %Event{
      set_power_levels("alice", %{})
      | event_id: "pl6",
        auth_events: [pl4],
        timestamp: 5
    }

    pl7 = %Event{
      set_power_levels("alice", %{})
      | event_id: "pl7",
        auth_events: [pl2],
        timestamp: 5
    }

    pl8 = %Event{
      set_power_levels("alice", %{})
      | event_id: "pl8",
        auth_events: [pl7],
        timestamp: 6
    }

    [pl1, pl2, pl3, pl4, pl5, pl6, pl7, pl8]
  end

  defp membership(user), do: membership(user, user)

  defp membership(actor, subject) do
    %Event{new() | event_type: :membership, sender: actor, state_key: subject}
  end

  defp get_event_power_level(%Event{state_key: ""}), do: 0
  defp get_event_power_level(_), do: 50
end
