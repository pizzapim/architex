defmodule MatrixServer do
  import Ecto.Changeset
  alias Ecto.Changeset

  def convert_change(changeset, old_name, new_name) do
    convert_change(changeset, old_name, new_name, &Function.identity/1)
  end

  def convert_change(changeset, old_name, new_name, f) do
    case changeset do
      %Changeset{valid?: true, changes: changes} ->
        case Map.fetch(changes, old_name) do
          {:ok, value} ->
            changeset
            |> put_change(new_name, f.(value))
            |> delete_change(old_name)

          :error ->
            changeset
        end

      _ ->
        changeset
    end
  end

  def validate_api_schema(params, {types, allowed, required}) do
    {%{}, types}
    |> cast(params, allowed)
    |> validate_required(required)
  end

  def generate_error(errcode) do
    {get_errcode_status(errcode), %{errcode: errcode, error: get_errcode_error(errcode)}}
  end

  # TODO: make a plug for this?
  def get_errcode_error("M_BAD_JSON"), do: "Bad request."
  def get_errcode_error("M_USER_IN_USE"), do: "Username is already taken."
  def get_errcode_error("M_INVALID_USERNAME"), do: "Invalid username."

  def get_errcode_status(_), do: 400

  def get_mxid(localpart) when is_binary(localpart) do
    "@#{localpart}:#{server_name()}"
  end

  def server_name do
    Application.get_env(:matrix_server, :server_name)
  end
end
