defmodule MatrixServer.Device do
  use Ecto.Schema

  import Ecto.{Changeset, Query}

  alias MatrixServer.{Account, Device, Repo}

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
    |> cast(params, [:display_name, :device_id])
    |> validate_required([:localpart, :device_id])
    |> unique_constraint([:localpart, :device_id], name: :devices_pkey)
  end

  def insert_new_access_token(repo, %{
        device: %Device{localpart: localpart, device_id: device_id} = device
      }) do
    access_token = generate_access_token(localpart, device_id)

    device
    |> change(%{access_token: access_token})
    |> repo.update()
  end

  def generate_access_token(localpart, device_id) do
    Phoenix.Token.encrypt(MatrixServerWeb.Endpoint, "access_token", {localpart, device_id})
  end

  def generate_device_id(localpart) do
    time_string =
      DateTime.utc_now()
      |> DateTime.to_unix()
      |> Integer.to_string()

    "#{localpart}_#{time_string}"
  end

  def login(account, device_id, access_token, params) do
    update_query =
      from(d in Device)
      |> update(set: [access_token: ^access_token, device_id: ^device_id])

    update_query =
      if params[:display_name] != nil do
        update(update_query, set: [display_name: ^params.display_name])
      else
        update_query
      end

    Ecto.build_assoc(account, :devices)
    |> Map.put(:device_id, device_id)
    |> Map.put(:access_token, access_token)
    |> Device.changeset(params)
    |> Repo.insert(on_conflict: update_query, conflict_target: [:localpart, :device_id])
  end
end
