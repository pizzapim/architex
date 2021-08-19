defmodule MatrixServer.StateResolution.Authorization do
  import MatrixServer.StateResolution
  import Ecto.Query

  alias MatrixServer.{Repo, Event}
  alias MatrixServer.Types.UserId
  alias MatrixServer.StateResolution, as: StateRes

  @typep action :: :invite | :ban | :redact | :kick | {:event, Event.t()}

  @spec authorized?(Event.t(), StateRes.state_set()) :: boolean()
  def authorized?(%Event{type: "m.room.create", prev_events: prev_events}, %{}),
    do: prev_events == []

  # Check rule: 5.2.1
  def authorized?(%Event{type: "m.room.member", state_key: state_key}, %{
        {"m.room.create", ""} => %Event{content: %{"creator" => creator}}
      }),
      do: state_key == creator

  def authorized?(
        %Event{type: "m.room.member", sender: sender, content: %{"membership" => "join"}},
        state_set
      ) do
    join_rule = get_join_rule(state_set)
    membership = get_membership(to_string(sender), state_set)

    # Check rules: 5.2.3, 5.2.4, 5.2.5
    cond do
      membership == "ban" -> false
      join_rule == "invite" -> membership in ["invite", "join"]
      join_rule == "public" -> true
      true -> false
    end
  end

  # TODO: rule 5.3.1
  def authorized?(
        %Event{
          type: "m.room.member",
          content: %{"membership" => "invite", "third_party_invite" => _}
        },
        _
      ),
      do: false

  def authorized?(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "invite"},
          state_key: state_key
        },
        state_set
      ) do
    sender_membership = get_membership(to_string(sender), state_set)
    target_membership = get_membership(state_key, state_set)
    power_levels = get_power_levels(state_set)

    # Check rules: 5.3.2, 5.3.3, 5.3.4
    cond do
      sender_membership != "join" -> false
      target_membership in ["join", "ban"] -> false
      has_power_level?(to_string(sender), power_levels, :invite) -> true
      true -> false
    end
  end

  def authorized?(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "leave"},
          state_key: sender
        },
        state_set
      ) do
    # Check rule: 5.4.1
    get_membership(to_string(sender), state_set) in ["invite", "join"]
  end

  def authorized?(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "leave"},
          state_key: state_key
        },
        state_set
      ) do
    sender_membership = get_membership(to_string(sender), state_set)
    target_membership = get_membership(state_key, state_set)
    power_levels = get_power_levels(state_set)
    sender_pl = get_user_power_level(to_string(sender), power_levels)
    target_pl = get_user_power_level(state_key, power_levels)

    # Check rules: 5.4.2, 5.4.3, 5.4.4
    cond do
      sender_membership != "join" ->
        false

      target_membership == "ban" and not has_power_level?(to_string(sender), power_levels, :ban) ->
        false

      has_power_level?(to_string(sender), power_levels, :kick) and target_pl < sender_pl ->
        true

      true ->
        false
    end
  end

  def authorized?(
        %Event{
          type: "m.room.member",
          sender: sender,
          content: %{"membership" => "ban"},
          state_key: state_key
        },
        state_set
      ) do
    sender_membership = get_membership(to_string(sender), state_set)
    power_levels = get_power_levels(state_set)
    sender_pl = get_user_power_level(to_string(sender), power_levels)
    target_pl = get_user_power_level(state_key, power_levels)

    # Check rules: 5.5.1, 5.5.2
    cond do
      sender_membership != "join" -> false
      has_power_level?(to_string(sender), power_levels, :ban) and target_pl < sender_pl -> true
      true -> false
    end
  end

  # Check rule: 5.6
  def authorized?(%Event{type: "m.room.member"}, _), do: false

  def authorized?(%Event{sender: sender} = event, state_set) do
    # Check rule: 6
    get_membership(to_string(sender), state_set) == "join" and _authorized?(event, state_set)
  end

  @spec _authorized?(Event.t(), StateRes.state_set()) :: boolean()
  defp _authorized?(%Event{type: "m.room.third_party_invite", sender: sender}, state_set) do
    power_levels = get_power_levels(state_set)
    # Check rule: 7.1

    has_power_level?(to_string(sender), power_levels, :invite)
  end

  defp _authorized?(%Event{state_key: state_key, sender: sender} = event, state_set) do
    power_levels = get_power_levels(state_set)

    # Check rules: 8, 9
    cond do
      not has_power_level?(to_string(sender), power_levels, {:event, event}) -> false
      String.starts_with?(state_key, "@") and state_key != sender -> false
      true -> __authorized?(event, state_set)
    end
  end

  @spec __authorized?(Event.t(), StateRes.state_set()) :: boolean()
  defp __authorized?(
         %Event{type: "m.room.power_levels", sender: sender, content: content},
         state_set
       ) do
    current_pls = get_power_levels(state_set)
    new_pls = content
    sender_pl = get_user_power_level(to_string(sender), new_pls)

    # Check rules: 10.2, 10.3, 10.4, 10.5
    cond do
      not is_map_key(state_set, {"m.room.power_levels", ""}) -> true
      not authorize_power_levels(sender, sender_pl, current_pls, new_pls) -> false
      true -> true
    end
  end

  # TODO: Rule 11

  defp __authorized?(_, _), do: true

  @spec get_power_levels(StateRes.state_set()) :: map() | nil
  defp get_power_levels(state_set) do
    with %Event{content: content} <- state_set[{"m.room.power_levels", ""}] do
      content
    end
  end

  @spec get_join_rule(StateRes.state_set()) :: String.t() | nil
  defp get_join_rule(state_set) do
    with %Event{content: %{"join_rule" => join_rule}} <- state_set[{"m.room.join_rules", ""}] do
      join_rule
    end
  end

  @spec get_membership(String.t(), StateRes.state_set()) :: String.t() | nil
  defp get_membership(user, state_set) do
    with %Event{content: %{"membership" => membership}} <- state_set[{"m.room.member", user}] do
      membership
    end
  end

  @spec has_power_level?(String.t(), map() | nil, action()) :: boolean()
  defp has_power_level?(user, power_levels, action) do
    user_pl = get_user_power_level(user, power_levels)
    action_pl = get_action_power_level(action, power_levels)

    user_pl >= action_pl
  end

  @spec get_user_power_level(String.t(), map() | nil) :: non_neg_integer()
  defp get_user_power_level(user, %{"users" => users}) when is_map_key(users, user),
    do: users[user]

  defp get_user_power_level(_, %{"users_default" => pl}), do: pl
  defp get_user_power_level(_, _), do: 0

  @spec get_action_power_level(action(), map() | nil) :: non_neg_integer()
  defp get_action_power_level(:invite, %{"invite" => pl}), do: pl
  defp get_action_power_level(:invite, _), do: 50
  defp get_action_power_level(:ban, %{"ban" => pl}), do: pl
  defp get_action_power_level(:ban, _), do: 50
  # defp get_action_power_level(:redact, %{"redact" => pl}), do: pl
  # defp get_action_power_level(:redact, _), do: 50
  defp get_action_power_level(:kick, %{"kick" => pl}), do: pl
  defp get_action_power_level(:kick, _), do: 50

  defp get_action_power_level({:event, %Event{type: type}}, %{"events" => events})
       when is_map_key(events, type),
       do: events[type]

  defp get_action_power_level({:event, event}, power_levels) do
    if Event.is_state_event(event) do
      case power_levels do
        %{"state_default" => pl} -> pl
        %{} -> 50
        nil -> 0
      end
    else
      case power_levels do
        %{"events_default" => pl} -> pl
        _ -> 0
      end
    end
  end

  # TODO: Power_levels may not have all these keys defined.
  @spec authorize_power_levels(UserId.t(), non_neg_integer(), map() | nil, map() | nil) ::
          boolean()
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
      valid_power_level_users_changes(current_users, new_users, to_string(user), user_pl)
  end

  defp authorize_power_levels(_, _, _, _), do: false

  @spec valid_power_level_key_changes(map(), map(), non_neg_integer()) :: boolean()
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

  def authorized_by_auth_events?(%Event{auth_events: auth_event_ids} = event) do
    # We assume the auth events are validated beforehand.
    state_set =
      Event
      |> where([e], e.event_id in ^auth_event_ids)
      |> Repo.all()
      |> Enum.reduce(%{}, &update_state_set/2)

    authorized?(event, state_set)
  end
end
