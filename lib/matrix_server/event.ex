defmodule MatrixServer.Event do
  use Ecto.Schema

  import Ecto.Query

  alias MatrixServer.{Repo, Room, Event, Account}

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

  def new(%Room{id: room_id}, %Account{localpart: localpart}) do
    %Event{
      room_id: room_id,
      sender: MatrixServer.get_mxid(localpart),
      event_id: generate_event_id(),
      origin_server_ts: DateTime.utc_now() |> DateTime.to_unix(),
      prev_events: [],
      auth_events: []
    }
  end

  def create_room(room, %Account{localpart: localpart} = creator, room_version) do
    mxid = MatrixServer.get_mxid(localpart)

    %Event{
      new(room, creator)
      | type: "m.room.create",
        state_key: "",
        content: %{
          "creator" => mxid,
          "room_version" => room_version || MatrixServer.default_room_version()
        }
    }
  end

  def join(room, %Account{localpart: localpart} = sender) do
    mxid = MatrixServer.get_mxid(localpart)

    %Event{
      new(room, sender)
      | type: "m.room.member",
        state_key: mxid,
        content: %{
          "membership" => "join"
        }
    }
  end

  def power_levels(room, %Account{localpart: localpart} = sender) do
    mxid = MatrixServer.get_mxid(localpart)

    %Event{
      new(room, sender)
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
            mxid => 50
          },
          "users_default" => 0,
          "notifications" => %{
            "room" => 50
          }
        }
    }
  end

  def name(room, sender, name) do
    %Event{
      new(room, sender)
      | type: "m.room.name",
        state_key: "",
        content: %{
          "name" => name
        }
    }
  end

  def topic(room, sender, topic) do
    %Event{
      new(room, sender)
      | type: "m.room.topic",
        state_key: "",
        content: %{
          "topic" => topic
        }
    }
  end

  def join_rules(room, sender, join_rule) do
    %Event{
      new(room, sender)
      | type: "m.room.join_rules",
        state_key: "",
        content: %{
          "join_rule" => join_rule
        }
    }
  end

  def history_visibility(room, sender, history_visibility) do
    %Event{
      new(room, sender)
      | type: "m.room.history_visibility",
        state_key: "",
        content: %{
          "history_visibility" => history_visibility
        }
    }
  end

  def guest_access(room, sender, guest_access) do
    %Event{
      new(room, sender)
      | type: "m.room.guest_access",
        state_key: "",
        content: %{
          "guest_access" => guest_access
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

  # Perform validations that can be done before state resolution.
  # For example checking the domain of the sender.
  # We assume that required keys, as well as in the content, is already validated.

  # Rule 1.4 is left to changeset validation.
  def prevalidate(%Event{
        type: "m.room.create",
        prev_events: prev_events,
        auth_events: auth_events,
        room_id: room_id,
        sender: sender
      }) do
    # TODO: error check on domains?
    # TODO: rule 1.3

    # Check rules: 1.1, 1.2
    prev_events == [] and
      auth_events == [] and
      MatrixServer.get_domain(sender) == MatrixServer.get_domain(room_id)
  end

  def prevalidate(%Event{auth_events: auth_event_ids, prev_events: prev_event_ids} = event) do
    prev_events =
      Event
      |> where([e], e.event_id in ^prev_event_ids)
      |> Repo.all()

    auth_events =
      Event
      |> where([e], e.event_id in ^auth_event_ids)
      |> Repo.all()

    state_pairs = Enum.map(auth_events, &{&1.type, &1.state_key})

    # Check rules: 2.1, 2.2, 3
    length(auth_events) == length(auth_event_ids) and
      length(prev_events) == length(prev_event_ids) and
      not MatrixServer.has_duplicates?(state_pairs) and
      valid_auth_events?(event, auth_events) and
      Enum.find_value(state_pairs, &(&1 == {"m.room.create", ""})) and
      do_prevalidate(event, auth_events, prev_events)
  end

  # Rule 4.1 is left to changeset validation.
  defp do_prevalidate(%Event{type: "m.room.aliases", sender: sender, state_key: state_key}, _, _) do
    # Check rule: 4.2
    MatrixServer.get_domain(sender) == MatrixServer.get_domain(state_key)
  end

  # Rule 5.1 is left to changeset validation.
  # Rules 5.2.3, 5.2.4, 5.2.5 is left to state resolution.
  # Check rule: 5.2.1
  defp do_prevalidate(
         %Event{type: "m.room.member", content: %{"membership" => "join"}, sender: sender},
         _,
         [%Event{type: "m.room.create", state_key: sender}]
       ),
       do: true

  # Check rule: 5.2.2
  defp do_prevalidate(
         %Event{
           type: "m.room.member",
           content: %{"membership" => "join"},
           sender: sender,
           state_key: state_key
         },
         _,
         _
       )
       when sender != state_key,
       do: false

  # All other rules will be checked during state resolution.
  defp do_prevalidate(_, _, _), do: true

  defp valid_auth_events?(
         %Event{type: type, sender: sender, state_key: state_key, content: content},
         auth_events
       ) do
    Enum.all?(auth_events, fn
      %Event{type: "m.room.create", state_key: ""} ->
        true

      %Event{type: "m.room.power_levels", state_key: ""} ->
        true

      %Event{type: "m.room.member", state_key: ^sender} ->
        true

      %Event{type: auth_type, state_key: auth_state_key} ->
        if type == "m.room.member" do
          %{"membership" => membership} = content

          (auth_type == "m.room.member" and auth_state_key == state_key) or
            (membership in ["join", "invite"] and auth_type == "m.room.join_rules" and
               auth_state_key == "") or
            (membership == "invite" and auth_type == "m.room.third_party_invite" and
               auth_state_key == "")
        else
          false
        end
    end)
  end
end
