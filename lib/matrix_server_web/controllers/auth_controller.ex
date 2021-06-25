defmodule MatrixServerWeb.AuthController do
  use MatrixServerWeb, :controller

  import MatrixServer

  alias MatrixServer.{Repo, Account}
  alias Ecto.Changeset

  @login_type "m.login.dummy"

  def register(conn, %{"auth" => %{"type" => @login_type}} = params) do
    # User has started an auth flow.
    result =
      case sanitize_register_params(params) do
        {:ok, params} ->
          case Repo.transaction(Account.register(params)) do
            {:ok, changeset} -> {:ok, changeset}
            {:error, _, changeset, _} -> {:error, get_register_error(changeset)}
          end

        {:error, changeset} ->
          {:error, get_register_error(changeset)}
      end

    {status, data} =
      case result do
        {:ok, %{device_with_access_token: device}} ->
          data = %{user_id: get_mxid(device.localpart)}

          data =
            if Map.get(params, "inhibit_login", false) == false do
              extra = %{device_id: device.device_id, access_token: device.access_token}
              Map.merge(data, extra)
            else
              data
            end

          {200, data}

        {:error, error} ->
          generate_error(error)
      end

    conn
    |> put_status(status)
    |> json(data)
  end

  def register(conn, %{"auth" => _}) do
    # Other login types are unsupported for now.
    data = %{errcode: "M_FORBIDDEN", error: "Login type not supported"}

    conn
    |> put_status(400)
    |> json(data)
  end

  def register(conn, _params) do
    # User has not started an auth flow.
    data = %{
      flows: [%{stages: [@login_type]}],
      params: %{}
    }

    conn
    |> put_status(401)
    |> json(data)
  end

  defp sanitize_register_params(params) do
    changeset =
      validate_api_schema(params, register_schema())
      |> convert_change(:username, :localpart)
      |> convert_change(:password, :password_hash, &Bcrypt.hash_pwd_salt/1)

    case changeset do
      %Changeset{valid?: true, changes: changes} -> {:ok, changes}
      _ -> {:error, changeset}
    end
  end

  defp get_register_error(%Changeset{errors: [error | _]}), do: get_register_error(error)
  defp get_register_error({:localpart, {_, [{:constraint, :unique} | _]}}), do: "M_USER_IN_USE"
  defp get_register_error({:localpart, {_, [{:validation, _} | _]}}), do: "M_INVALID_USERNAME"
  defp get_register_error(_), do: "M_BAD_JSON"

  defp register_schema do
    types = %{
      device_id: :string,
      initial_device_display_name: :string,
      display_name: :string,
      password: :string,
      username: :string,
      localpart: :string,
      password_hash: :string,
      access_token: :string
    }

    allowed = [:device_id, :initial_device_display_name, :username, :password]
    required = [:username, :password]

    {types, allowed, required}
  end

  def login(conn, _params) do
    data = %{flows: [%{type: @login_type}]}

    conn
    |> put_status(200)
    |> json(data)
  end
end
