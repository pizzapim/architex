defmodule MatrixServerWeb.API.Register do
  use Ecto.Schema

  import Ecto.Changeset
  import MatrixServerWeb.Plug.Error

  alias Ecto.Changeset

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
    |> validate_required([:password, :username])
  end

  def handle_error(conn, cs) do
    put_error(conn, get_register_error(cs))
  end

  defp get_register_error(%Changeset{errors: [error | _]}), do: get_register_error(error)
  defp get_register_error({:localpart, {_, [{:constraint, :unique} | _]}}), do: :user_in_use
  defp get_register_error({:localpart, {_, [{:validation, _} | _]}}), do: :invalid_username
  defp get_register_error(_), do: :bad_json
end
