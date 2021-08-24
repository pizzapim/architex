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
