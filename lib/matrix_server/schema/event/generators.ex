defmodule MatrixServer.Event.Join do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t()) :: Event.t()
  def new(room, %Account{localpart: localpart} = sender) do
    mxid = MatrixServer.get_mxid(localpart)

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: mxid,
        content: %{
          "membership" => "join"
        }
    }
  end
end

defmodule MatrixServer.Event.CreateRoom do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
  def new(room, %Account{localpart: localpart} = creator, room_version) do
    mxid = MatrixServer.get_mxid(localpart)

    %Event{
      Event.new(room, creator)
      | type: "m.room.create",
        state_key: "",
        content: %{
          "creator" => mxid,
          "room_version" => room_version || MatrixServer.default_room_version()
        }
    }
  end
end

defmodule MatrixServer.Event.PowerLevels do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t()) :: Event.t()
  def new(room, %Account{localpart: localpart} = sender) do
    mxid = MatrixServer.get_mxid(localpart)

    %Event{
      Event.new(room, sender)
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
end

defmodule MatrixServer.Event.Name do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
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

defmodule MatrixServer.Event.Topic do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
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

defmodule MatrixServer.Event.JoinRules do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
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

defmodule MatrixServer.Event.HistoryVisibility do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
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

defmodule MatrixServer.Event.GuestAccess do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
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

defmodule MatrixServer.Event.Invite do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
  def new(room, sender, user_id) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: %{
          "membership" => "invite"
        }
    }
  end
end

defmodule MatrixServer.Event.Leave do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t()) :: Event.t()
  def new(room, sender) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: Account.get_mxid(sender),
        content: %{
          "membership" => "leave"
        }
    }
  end
end

defmodule MatrixServer.Event.Kick do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t(), String.t() | nil) :: Event.t()
  def new(room, sender, user_id, reason \\ nil) do
    content = %{"membership" => "leave"}
    content = if reason, do: Map.put(content, "reason", reason), else: content

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: content
    }
  end
end

defmodule MatrixServer.Event.Ban do
  alias MatrixServer.{Event, Account, Room}

  @spec new(Room.t(), Account.t(), String.t(), String.t() | nil) :: Event.t()
  def new(room, sender, user_id, reason \\ nil) do
    content = %{"membership" => "ban"}
    content = if reason, do: Map.put(content, "reason", reason), else: content

    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: content
    }
  end
end

defmodule MatrixServer.Event.Unban do
  alias MatrixServer.{Event, Account, Room}
  @spec new(Room.t(), Account.t(), String.t()) :: Event.t()
  def new(room, sender, user_id) do
    %Event{
      Event.new(room, sender)
      | type: "m.room.member",
        state_key: user_id,
        content: %{
          "membership" => "leave"
        }
    }
  end
end
