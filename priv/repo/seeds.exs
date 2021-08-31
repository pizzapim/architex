alias MatrixServer.{Repo, Account}

account =
  Repo.insert!(%Account{
    localpart: "chuck",
    password_hash: Bcrypt.hash_pwd_salt("sneed")
  })

account
|> Ecto.build_assoc(:devices,
  device_id: "android",
  display_name: "My Android",
  access_token: "sneed"
)
|> Repo.insert!()
