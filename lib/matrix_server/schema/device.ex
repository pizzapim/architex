defmodule MatrixServer.Device do
  use Ecto.Schema

  import Ecto.{Changeset, Query}

  alias MatrixServer.{Account, Device, Repo}
  alias MatrixServerWeb.Client.Request.Login

  @type t :: %__MODULE__{
          device_id: String.t(),
          access_token: String.t(),
          display_name: String.t(),
          account_id: integer()
        }

  schema "devices" do
    field :device_id, :string
    field :access_token, :string, redact: true
    field :display_name, :string

    belongs_to :account, Account
  end

  def changeset(device, params \\ %{}) do
    device
    |> cast(params, [:display_name, :device_id])
    |> validate_required([:device_id])
    |> unique_constraint([:device_id, :account_id], name: :devices_device_id_account_id_index)
  end

  def generate_access_token(localpart, device_id) do
    Phoenix.Token.encrypt(MatrixServerWeb.Endpoint, "access_token", {localpart, device_id})
  end

  def generate_device_id(localpart) do
    # TODO: use random string instead
    "#{localpart}_#{System.os_time(:millisecond)}"
  end

  def login(
        %Login{device_id: device_id, initial_device_display_name: initial_device_display_name},
        %Account{localpart: localpart} = account
      ) do
    device_id = device_id || generate_device_id(localpart)
    access_token = generate_access_token(localpart, device_id)

    update_query =
      from(d in Device)
      |> update(set: [access_token: ^access_token, device_id: ^device_id])
      |> then(fn q ->
        if initial_device_display_name do
          update(q, set: [display_name: ^initial_device_display_name])
        else
          q
        end
      end)

    device_params = %{
      device_id: device_id,
      display_name: initial_device_display_name
    }

    Ecto.build_assoc(account, :devices)
    |> Device.changeset(device_params)
    |> put_change(:access_token, access_token)
    |> Repo.insert(on_conflict: update_query, conflict_target: [:account_id, :device_id])
  end
end
