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
    create_room(room_id, MatrixServer.get_mxid(localpart), room_version)
    |> repo.insert()
  end

  def room_creation_join_creator(repo, %{
        room: %Room{id: room_id},
        create_room_event: %Event{sender: creator}
      }) do
    # TODO: state resolution
    join(room_id, creator)
    |> repo.insert()
  end

  def room_creation_power_levels(
        repo,
        %{
          room: %Room{id: room_id},
          create_room_event: %Event{sender: creator}
        }
      ) do
    # TODO: state resolution
    power_levels(room_id, creator)
    |> repo.insert()
  end

  def room_creation_name(_repo, %{input: %CreateRoom{name: nil}}), do: {:ok, :noop}

  def room_creation_name(
        repo,
        %{
          input: %CreateRoom{name: name},
          room: %Room{id: room_id},
          create_room_event: %Event{sender: creator}
        }
      ) do
    # TODO: state resolution
    # TODO: check name length
    room_name(room_id, creator, name)
    |> repo.insert()
  end

  def room_creation_topic(_repo, %{input: %CreateRoom{topic: nil}}), do: {:ok, :noop}

  def room_creation_topic(
        repo,
        %{
          input: %CreateRoom{topic: topic},
          room: %Room{id: room_id},
          create_room_event: %Event{sender: creator}
        }
      ) do
    # TODO: state resolution
    room_topic(room_id, creator, topic)
    |> repo.insert()
  end

  def generate_event_id do
    "$" <> MatrixServer.random_string(17) <> ":" <> MatrixServer.server_name()
  end
end
