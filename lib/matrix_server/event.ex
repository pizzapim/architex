defmodule MatrixServer.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias MatrixServer.{Room, Event}

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
          "membership" => "join"
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

  def generate_event_id do
    "$" <> MatrixServer.random_string(17) <> ":" <> MatrixServer.server_name()
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

  def is_state_event(%Event{state_key: state_key}), do: state_key != nil
end
