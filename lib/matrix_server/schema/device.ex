defmodule MatrixServer.Device do
  use Ecto.Schema

  import Ecto.{Changeset, Query}

  alias MatrixServer.{Account, Device, Repo}
  alias MatrixServerWeb.Client.Request.Login

  @primary_key false
  schema "devices" do
    field :device_id, :string, primary_key: true
    field :access_token, :string, redact: true
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
    # TODO: use random string instead
    "#{localpart}_#{System.os_time(:millisecond)}"
  end

  def login(%Login{} = input, account) do
    device_id = input.device_id || generate_device_id(account.localpart)
    access_token = generate_access_token(account.localpart, device_id)

    update_query =
      from(d in Device)
      |> update(set: [access_token: ^access_token, device_id: ^device_id])
      |> then(fn q ->
        if input.initial_device_display_name do
          update(q, set: [display_name: ^input.initial_device_display_name])
        else
          q
        end
      end)

    device_params = %{
      device_id: device_id,
      display_name: input.initial_device_display_name
    }

    Ecto.build_assoc(account, :devices)
    |> Device.changeset(device_params)
    |> put_change(:access_token, access_token)
    |> Repo.insert(on_conflict: update_query, conflict_target: [:localpart, :device_id])
  end
end
