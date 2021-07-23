alias MatrixServer.{Repo, Room, Event, Account, Device}

Repo.insert!(%Account{
  localpart: "chuck",
  password_hash: Bcrypt.hash_pwd_salt("sneed")
})

Repo.insert(%Device{
  device_id: "android",
  display_name: "My Android",
  localpart: "chuck"
})

# Auth difference example from here:
# https://matrix.org/docs/guides/implementing-stateres#auth-differences

Repo.insert!(%Room{
  id: "room1",
  visibility: :public
})

Repo.insert!(
  Event.create_room("room1", "alice", "v1")
  |> Map.put(:origin_server_ts, 0)
  |> Map.put(:event_id, "create")
)

Repo.insert!(
  Event.join("room1", "alice")
  |> Map.put(:prev_events, ["create"])
  |> Map.put(:auth_events, ["create"])
  |> Map.put(:origin_server_ts, 1)
  |> Map.put(:event_id, "join_alice")
)

Repo.insert!(
  Event.join("room1", "bob")
  |> Map.put(:prev_events, ["join_alice"])
  |> Map.put(:auth_events, ["create"])
  |> Map.put(:origin_server_ts, 2)
  |> Map.put(:event_id, "join_bob")
)

Repo.insert!(
  Event.join("room1", "charlie")
  |> Map.put(:prev_events, ["join_bob"])
  |> Map.put(:auth_events, ["create"])
  |> Map.put(:origin_server_ts, 3)
  |> Map.put(:event_id, "join_charlie")
)

%Event{content: content} = event = Event.power_levels("room1", "alice")
event = %Event{event | content: %{content | "users" => %{"alice" => 100, "bob" => 100}}}

Repo.insert!(
  event
  |> Map.put(:prev_events, ["join_alice"])
  |> Map.put(:auth_events, ["create", "join_alice"])
  |> Map.put(:origin_server_ts, 4)
  |> Map.put(:event_id, "a")
)

%Event{content: content} = event = Event.power_levels("room1", "bob")

event = %Event{
  event
  | content: %{content | "users" => %{"alice" => 100, "bob" => 100, "charlie" => 100}}
}

Repo.insert!(
  event
  |> Map.put(:prev_events, ["a"])
  |> Map.put(:auth_events, ["create", "join_bob", "a"])
  |> Map.put(:origin_server_ts, 5)
  |> Map.put(:event_id, "b")
)

Repo.insert!(
  Event.room_topic("room1", "alice", "sneed")
  |> Map.put(:prev_events, ["a"])
  |> Map.put(:auth_events, ["create", "join_alice", "a"])
  |> Map.put(:origin_server_ts, 5)
  |> Map.put(:event_id, "fork")
)
