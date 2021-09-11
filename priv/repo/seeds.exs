alias Architex.{Repo, Account}

account =
  Repo.insert!(%Account{
    localpart: "chuck",
    password_hash: Bcrypt.hash_pwd_salt("sneed")
  })

account
|> Ecto.build_assoc(:devices,
  id: "android",
  display_name: "My Android",
  access_token: "sneed"
)
|> Repo.insert!()

account =
  Repo.insert!(%Account{
    localpart: "steamed",
    password_hash: Bcrypt.hash_pwd_salt("hams")
  })

account
|> Ecto.build_assoc(:devices,
  id: "iPhone",
  display_name: "My iPhone",
  access_token: "hams"
)
|> Repo.insert!()
