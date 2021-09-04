defmodule Architex.Factory do
  use ExMachina.Ecto, repo: Architex.Repo

  alias Architex.{Account, Device}

  def account_factory do
    %Account{
      localpart: sequence(:localpart, &"account#{&1}"),
      password_hash: Bcrypt.hash_pwd_salt("lemmein")
    }
  end

  def device_factory do
    %Account{localpart: localpart} = account = build(:account)
    device_id = sequence(:device_id, &"device#{&1}")

    %Device{
      id: device_id,
      access_token: Device.generate_access_token(localpart, device_id),
      display_name: sequence(:display_name, &"Device #{&1}"),
      account: account
    }
  end
end
