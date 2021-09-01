defmodule ArchitexWeb.Client.Request.Register do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          device_id: String.t(),
          initial_device_display_name: String.t(),
          password: String.t(),
          username: String.t(),
          inhibit_login: boolean()
        }

  @primary_key false
  embedded_schema do
    field :device_id, :string
    field :initial_device_display_name, :string
    field :password, :string
    field :username, :string
    field :inhibit_login, :boolean, default: false
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :device_id,
      :initial_device_display_name,
      :password,
      :username,
      :inhibit_login
    ])
    |> validate_required([:password])
  end

  def get_error(%Changeset{errors: [error | _]}), do: get_error(error)
  def get_error({:localpart, {_, [{:constraint, :unique} | _]}}), do: :user_in_use
  def get_error({:localpart, {_, [{:validation, _} | _]}}), do: :invalid_username
  def get_error(_), do: :bad_json
end
