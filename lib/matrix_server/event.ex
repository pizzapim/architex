defmodule MatrixServer.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias MatrixServer.{Room, Event, Account}
  alias MatrixServerWeb.API.CreateRoom

  @primary_key {:event_id, :string, []}
  schema "events" do
    field :type, :string
    field :origin_server_ts, :integer
    field :state_key, :string
    field :sender, :string
    field :content, :map
    field :prev_events, {:array, :string}
    field :auth_events, {:array, :string}
    belongs_to :room, Room, type: :string
  end

  def changeset(event, params \\ %{}) do
    # TODO: prev/auth events?
    event
    |> cast(params, [:type, :timestamp, :state_key, :sender, :content])
    |> validate_required([:type, :timestamp, :sender])
  end

  def new(room_id, sender) do
    %Event{
      room_id: room_id,
      sender: sender,
      event_id: generate_event_id(),
      origin_server_ts: DateTime.utc_now() |> DateTime.to_unix(),
      prev_events: [],
      auth_events: []
    }
  end

  def create_room(room_id, creator, room_version) do
    %Event{
      new(room_id, creator)
      | type: "m.room.create",
        state_key: "",
        content: %{
          "creator" => creator,
          "room_version" => room_version || MatrixServer.default_room_version()
        }
    }
  end

  def join(room_id, sender) do
    %Event{
      new(room_id, sender)
      | type: "m.room.member",
        state_key: sender,
        content: %{
          "membership" => "invite"
        }
    }
  end

  def power_levels(room_id, sender) do
    %Event{
      new(room_id, sender)
      | type: "m.room.power_levels",
        state_key: "",
        content: %{
          "ban" => 50,
          "events" => %{},
          "events_default" => 0,
          "invite" => 50,
          "kick" => 50,
          "redact" => 50,
          "state_default" => 50,
          "users" => %{
            sender => 50
          },
          "users_default" => 0,
          "notifications" => %{
            "room" => 50
          }
        }
    }
  end

  def room_name(room_id, sender, name) do
    %Event{
      new(room_id, sender)
      | type: "m.room.name",
        state_key: "",
        content: %{
          "name" => name
        }
    }
  end

  def room_topic(room_id, sender, topic) do
    %Event{
      new(room_id, sender)
      | type: "m.room.topic",
        state_key: "",
        content: %{
          "topic" => topic
        }
    }
  end

  def room_creation_create_room(repo, %{
        input: %CreateRoom{room_version: room_version},
        account: %Account{localpart: localpart},
        room: %Room{id: room_id}
      }) do
    # TODO: state resolution
    create_room_event = create_room(room_id, MatrixServer.get_mxid(localpart), room_version)
    resolve([events_to_state_set([create_room_event])])
    repo.insert(create_room_event)
  end

  def room_creation_join_creator(repo, %{
        room: %Room{id: room_id},
        create_room_event: %Event{sender: creator, event_id: create_room_id}
      }) do
    # TODO: state resolution
    join(room_id, creator)
    |> Map.put(:prev_events, [create_room_id])
    |> Map.put(:auth_events, [create_room_id])
    |> repo.insert()
  end

  def room_creation_power_levels(
        repo,
        %{
          room: %Room{id: room_id},
          create_room_event: %Event{sender: creator, event_id: create_room_id},
          join_creator_event: %Event{event_id: join_creator_id}
        }
      ) do
    # TODO: state resolution
    power_levels(room_id, creator)
    |> Map.put(:prev_events, [join_creator_id])
    |> Map.put(:auth_events, [create_room_id, join_creator_id])
    |> repo.insert()
  end

  def room_creation_name(_repo, %{input: %CreateRoom{name: nil}}), do: {:ok, nil}

  def room_creation_name(_repo, %{input: %CreateRoom{name: name}}) when byte_size(name) > 255,
    do: {:error, :name}

  def room_creation_name(
        repo,
        %{
          input: %CreateRoom{name: name},
          room: %Room{id: room_id},
          create_room_event: %Event{sender: creator, event_id: create_room_id},
          join_creator_event: %Event{event_id: join_creator_id},
          power_levels_event: %Event{event_id: power_levels_id}
        }
      ) do
    # TODO: state resolution
    room_name(room_id, creator, name)
    |> Map.put(:prev_events, [power_levels_id])
    |> Map.put(:auth_events, [create_room_id, join_creator_id, power_levels_id])
    |> repo.insert()
  end

  def room_creation_topic(_repo, %{input: %CreateRoom{topic: nil}}), do: {:ok, nil}

  def room_creation_topic(
        repo,
        %{
          input: %CreateRoom{topic: topic},
          room: %Room{id: room_id},
          create_room_event: %Event{sender: creator, event_id: create_room_id},
          join_creator_event: %Event{event_id: join_creator_id},
          power_levels_event: %Event{event_id: power_levels_id},
          name_event: name_event
        }
      ) do
    # TODO: state resolution
    prev_event = if name_event, do: name_event.event_id, else: power_levels_id

    room_topic(room_id, creator, topic)
    |> Map.put(:prev_events, [prev_event])
    |> Map.put(:auth_events, [create_room_id, join_creator_id, power_levels_id])
    |> repo.insert()
  end

  def generate_event_id do
    "$" <> MatrixServer.random_string(17) <> ":" <> MatrixServer.server_name()
  end

  def events_to_state_set(events) do
    Enum.into(events, %{}, fn %Event{type: type, state_key: state_key} = event ->
      {{type, state_key}, event}
    end)
  end

  def resolve(state_sets) do
    {unconflicted_state_map, conflicted_set} = calculate_conflict(state_sets)
    # full_conflicted_set = MapSet.union(conflicted_set, auth_difference(state_sets))

    # conflicted_control_events =
    #   Enum.filter(full_conflicted_set, &is_control_event/1) |> MapSet.new()

    # conflicted_control_events_with_auth =
    #   MapSet.union(
    #     conflicted_control_events,
    #     MapSet.intersection(
    #       full_conflicted_set,
    #       full_auth_chain(MapSet.to_list(conflicted_control_events))
    #     )
    #   )

    # sorted_control_events = Enum.sort(conflicted_control_events_with_auth, &rev_top_pow_order/2)
    # partial_resolved_state = iterative_auth_checks(sorted_control_events, unconflicted_state_map)

    # other_conflicted_events =
    #   MapSet.difference(full_conflicted_set, conflicted_control_events_with_auth)

    # resolved_power_levels = partial_resolved_state[{:power_levels, ""}]

    # sorted_other_events =
    #   Enum.sort(other_conflicted_events, mainline_order(resolved_power_levels))

    # nearly_final_state = iterative_auth_checks(sorted_other_events, partial_resolved_state)

    # Map.merge(nearly_final_state, unconflicted_state_map)
  end

  def calculate_conflict(state_sets) do
    {unconflicted, conflicted} =
      state_sets
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()
      |> Enum.map(fn state_pair ->
        events =
          Enum.map(state_sets, &Map.get(&1, state_pair))
          |> MapSet.new()

        {state_pair, events}
      end)
      |> Enum.split_with(fn {_k, events} ->
        MapSet.size(events) == 1
      end)

    unconflicted_state_map = Enum.into(unconflicted, %{}, fn {state_pair, events} ->
      event = MapSet.to_list(events) |> hd()

      {state_pair, event}
    end)

    conflicted_state_set = Enum.reduce(conflicted, MapSet.new(), fn {_, events}, acc ->
      MapSet.union(acc, events)
    end)
    |> MapSet.delete(nil)

    {unconflicted_state_map, conflicted_state_set}
  end
end
