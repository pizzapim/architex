alias MatrixServer.{Repo, Room, Event, Account, Device}

timestamp = fn n -> DateTime.from_unix!(n, :microsecond) end

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

alice =
  Repo.insert!(%Account{
    localpart: "alice",
    password_hash: Bcrypt.hash_pwd_salt("sneed")
  })

bob =
  Repo.insert!(%Account{
    localpart: "bob",
    password_hash: Bcrypt.hash_pwd_salt("sneed")
  })

charlie =
  Repo.insert!(%Account{
    localpart: "charlie",
    password_hash: Bcrypt.hash_pwd_salt("sneed")
  })

room =
  Repo.insert!(%Room{
    id: "room1",
    visibility: :public
  })

Repo.insert!(
  Event.create_room(room, alice, "v1")
  |> Map.put(:origin_server_ts, timestamp.(0))
  |> Map.put(:event_id, "create")
)

Repo.insert!(
  Event.join(room, alice)
  |> Map.put(:prev_events, ["create"])
  |> Map.put(:auth_events, ["create"])
  |> Map.put(:origin_server_ts, timestamp.(1))
  |> Map.put(:event_id, "join_alice")
)

Repo.insert!(
  Event.join(room, bob)
  |> Map.put(:prev_events, ["join_alice"])
  |> Map.put(:auth_events, ["create"])
  |> Map.put(:origin_server_ts, timestamp.(2))
  |> Map.put(:event_id, "join_bob")
)

Repo.insert!(
  Event.join(room, charlie)
  |> Map.put(:prev_events, ["join_bob"])
  |> Map.put(:auth_events, ["create"])
  |> Map.put(:origin_server_ts, timestamp.(3))
  |> Map.put(:event_id, "join_charlie")
)

%Event{content: content} = event = Event.power_levels(room, alice)
event = %Event{event | content: %{content | "users" => %{"alice" => 100, "bob" => 100}}}

Repo.insert!(
  event
  |> Map.put(:prev_events, ["join_alice"])
  |> Map.put(:auth_events, ["create", "join_alice"])
  |> Map.put(:origin_server_ts, timestamp.(4))
  |> Map.put(:event_id, "a")
)

%Event{content: content} = event = Event.power_levels(room, bob)

event = %Event{
  event
  | content: %{content | "users" => %{"alice" => 100, "bob" => 100, "charlie" => 100}}
}

Repo.insert!(
  event
  |> Map.put(:prev_events, ["a"])
  |> Map.put(:auth_events, ["create", "join_bob", "a"])
  |> Map.put(:origin_server_ts, timestamp.(5))
  |> Map.put(:event_id, "b")
)

Repo.insert!(
  Event.topic(room, alice, "sneed")
  |> Map.put(:prev_events, ["a"])
  |> Map.put(:auth_events, ["create", "join_alice", "a"])
  |> Map.put(:origin_server_ts, timestamp.(5))
  |> Map.put(:event_id, "fork")
)
