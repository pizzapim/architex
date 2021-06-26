defmodule MatrixServer.Device do
  use Ecto.Schema
  import Ecto.Changeset
  alias MatrixServer.{Account, Device}

  @primary_key false
  schema "devices" do
    field :device_id, :string, primary_key: true
    field :access_token, :string
    field :display_name, :string

    belongs_to :account, Account,
      foreign_key: :localpart,
      references: :localpart,
      type: :string,
      primary_key: true
  end

  def changeset(device, params \\ %{}) do
    device
    |> cast(params, [:localpart, :device_id, :access_token, :display_name])
    |> validate_required([:localpart, :device_id])
    |> unique_constraint([:localpart, :device_id], name: :devices_pkey)
  end

  def generate_access_token(repo, %{
        device: %Device{localpart: localpart, device_id: device_id} = device
      }) do
    access_token =
      Phoenix.Token.encrypt(MatrixServerWeb.Endpoint, "access_token", {localpart, device_id})

    device
    |> change(%{access_token: access_token})
    |> repo.update()
  end

  def generate_device_id(%Account{localpart: localpart}) do
    time_string =
      DateTime.utc_now()
      |> DateTime.to_unix()
      |> Integer.to_string()

    "#{localpart}_#{time_string}"
  end
end
