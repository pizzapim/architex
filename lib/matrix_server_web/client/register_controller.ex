defmodule MatrixServerWeb.Client.RegisterController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error
  import Ecto.Changeset

  alias MatrixServer.{Repo, Account}
  alias MatrixServerWeb.Request.Register
  alias Ecto.Changeset

  @register_type "m.login.dummy"

  def register(conn, %{"auth" => %{"type" => @register_type}} = params) do
    case Register.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input = apply_changes(cs)

        case Account.register(input) |> Repo.transaction() do
          {:ok, %{device_with_access_token: device}} ->
            data = %{user_id: MatrixServer.get_mxid(device.localpart)}

            data =
              if not input.inhibit_login do
                data
                |> Map.put(:device_id, device.device_id)
                |> Map.put(:access_token, device.access_token)
              else
                data
              end

            conn
            |> put_status(200)
            |> json(data)

          {:error, _, cs, _} ->
            put_error(conn, Register.get_error(cs))
        end

      _ ->
        put_error(conn, :bad_json)
    end
  end

  def register(conn, %{"auth" => _}) do
    # Other login types are unsupported for now.
    put_error(conn, :unrecognized, "Only m.login.dummy is supported currently.")
  end

  def register(conn, _params) do
    # User has not started an auth flow.
    data = %{
      flows: [%{stages: [@register_type]}],
      params: %{}
    }

    conn
    |> put_status(401)
    |> json(data)
  end
end
