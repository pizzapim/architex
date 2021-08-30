alias MatrixServer.{Repo, Account, Device}

Repo.insert!(%Account{
  localpart: "chuck",
  password_hash: Bcrypt.hash_pwd_salt("sneed")
})

Repo.insert(%Device{
  device_id: "android",
  display_name: "My Android",
  localpart: "chuck"
})
