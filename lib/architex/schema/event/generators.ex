defmodule Architex.Event.Join do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t()) :: %Event{}
  def new(
        room,
        %Account{localpart: localpart, avatar_url: avatar_url, displayname: displayname} = sender
      ) do
    mxid = Architex.get_mxid(localpart)

    content =
      Event.default_membership_content(avatar_url, displayname)
      |> Map.put("membership", "join")

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: mxid,
        content: content
    }
  end
end

defmodule Architex.Event.CreateRoom do
  alias Architex.{Event, Account, Room}

  @clobber_content_keys ["creator", "room_version"]

  @spec new(Room.t(), Account.t(), String.t(), %{optional(String.t()) => any()} | nil) :: %Event{}
  def new(room, %Account{localpart: localpart} = creator, room_version, creation_content) do
    mxid = Architex.get_mxid(localpart)

    content = %{
      "creator" => mxid,
      "room_version" => room_version || Architex.default_room_version()
    }

    content =
      if creation_content do
        creation_content
        |> Map.drop(@clobber_content_keys)
        |> Map.merge(content)
      else
        content
      end

    %Event{
      Event.new(room, creator)
      | type: "m.room.create",
        state_key: "",
        content: content
    }
  end
end

defmodule Architex.Event.PowerLevels do
  alias Architex.{Event, Account, Room}
  alias Architex.Types.UserId
  alias ArchitexWeb.Client.Request.CreateRoom
  alias ArchitexWeb.Client.Request.CreateRoom.PowerLevelContentOverride

  @ban 50
  @events_default 0
  @invite 50
  @kick 50
  @redact 50
  @state_default 50
  @creator 50
  @users_default 0
  @notifications_room 50

  @spec create_room_new(
          Room.t(),
          Account.t(),
          CreateRoom.PowerLevelContentOverride.t(),
          [UserId.t()] | nil,
          String.t() | nil
        ) :: %Event{}
  def create_room_new(room, sender, nil, invite_ids, preset) do
    create_room_new(room, sender, %PowerLevelContentOverride{}, invite_ids, preset)
  end

  def create_room_new(
        room,
        %Account{localpart: localpart} = sender,
        %PowerLevelContentOverride{
          ban: ban_override,
          events: events_override,
          events_default: events_default_override,
          invite: invite_override,
          kick: kick_override,
          redact: redact_override,
          state_default: state_default_override,
          users: users_override,
          users_default: users_default_override,
          notifications: notifications_override
        },
        invite_ids,
        preset
      ) do
    mxid = Architex.get_mxid(localpart)
    users = %{mxid => @creator}
    users = if users_override, do: Map.merge(users, users_override), else: users
    creator_pl = users[mxid]

    # Give each invitee the same power level as the creator.
    # This overrides the content override, but the spec is not clear on this.
    users =
      if preset == "trusted_private_chat" and invite_ids do
        invite_users_pls = Enum.into(invite_ids, %{}, &{to_string(&1), creator_pl})
        Map.merge(users, invite_users_pls)
      else
        users
      end

    notifications =
      case notifications_override do
        %{room: room} -> %{"room" => room}
        _ -> %{"room" => @notifications_room}
      end

    %Event{
      Event.new(room, sender)
      | type: "m.room.power_levels",
        state_key: "",
        content: %{
          "ban" => ban_override || @ban,
          "events" => events_override || %{},
          "events_default" => events_default_override || @events_default,
          "invite" => invite_override || @invite,
          "kick" => kick_override || @kick,
          "redact" => redact_override || @redact,
          "state_default" => state_default_override || @state_default,
          "users" => users,
          "users_default" => users_default_override || @users_default,
          "notifications" => notifications
        }
    }
  end
end

defmodule Architex.Event.Name do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: %Event{}
  def new(room, sender, name) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.name",
        state_key: "",
        content: %{
          "name" => name
        }
    }
  end
end

defmodule Architex.Event.Topic do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: %Event{}
  def new(room, sender, topic) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.topic",
        state_key: "",
        content: %{
          "topic" => topic
        }
    }
  end
end

defmodule Architex.Event.JoinRules do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: %Event{}
  def new(room, sender, join_rule) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.join_rules",
        state_key: "",
        content: %{
          "join_rule" => join_rule
        }
    }
  end
end

defmodule Architex.Event.HistoryVisibility do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: %Event{}
  def new(room, sender, history_visibility) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.history_visibility",
        state_key: "",
        content: %{
          "history_visibility" => history_visibility
        }
    }
  end
end

defmodule Architex.Event.GuestAccess do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: %Event{}
  def new(room, sender, guest_access) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.guest_access",
        state_key: "",
        content: %{
          "guest_access" => guest_access
        }
    }
  end
end

defmodule Architex.Event.Invite do
  alias Architex.{Event, Account, Room}

  @spec new(
          Room.t(),
          Account.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          boolean() | nil
        ) :: %Event{}
  def new(room, sender, user_id, avatar_url, displayname, is_direct \\ nil) do
    content =
      Event.default_membership_content(avatar_url, displayname)
      |> Map.put("membership", "invite")

    content = if is_direct != nil, do: Map.put(content, "is_direct", is_direct), else: content

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: content
    }
  end
end

defmodule Architex.Event.Leave do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t()) :: %Event{}
  def new(room, %Account{avatar_url: avatar_url, displayname: displayname} = sender) do
    content =
      Event.default_membership_content(avatar_url, displayname)
      |> Map.put("membership", "leave")

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: Account.get_mxid(sender),
        content: content
    }
  end
end

defmodule Architex.Event.Kick do
  alias Architex.{Event, Account, Room}

  @spec new(
          Room.t(),
          Account.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: %Event{}
  def new(room, sender, user_id, avatar_url, displayname, reason \\ nil) do
    content =
      Event.default_membership_content(avatar_url, displayname)
      |> Map.put("membership", "leave")

    content = if reason, do: Map.put(content, "reason", reason), else: content

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: content
    }
  end
end

defmodule Architex.Event.Ban do
  alias Architex.{Event, Account, Room}

  @spec new(
          Room.t(),
          Account.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: %Event{}
  def new(room, sender, user_id, avatar_url, displayname, reason \\ nil) do
    content =
      Event.default_membership_content(avatar_url, displayname)
      |> Map.put("membership", "ban")

    content = if reason, do: Map.put(content, "reason", reason), else: content

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: content
    }
  end
end

defmodule Architex.Event.Unban do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t(), String.t() | nil, String.t() | nil) :: %Event{}
  def new(room, sender, avatar_url, displayname, user_id) do
    content =
      Event.default_membership_content(avatar_url, displayname)
      |> Map.put("membership", "leave")

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: content
    }
  end
end

defmodule Architex.Event.CanonicalAlias do
  alias Architex.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t() | nil, [String.t()] | nil) :: %Event{}
  def new(room, sender, alias_ \\ nil, alt_aliases \\ nil) do
    content = %{}
    content = if alias_, do: Map.put(content, "alias", alias_), else: content
    content = if alt_aliases, do: Map.put(content, "alt_aliases", alt_aliases), else: content

    %Event{
      Event.new(room, sender)
      | type: "m.room.canonical_alias",
        state_key: "",
        content: content
    }
  end
end
