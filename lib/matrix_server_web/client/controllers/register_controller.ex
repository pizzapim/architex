defmodule MatrixServerWeb.Client.RegisterController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Error
  import Ecto.Changeset

  alias MatrixServer.{Repo, Account, Device}
  alias MatrixServerWeb.Client.Request.Register
  alias Ecto.Changeset

  @register_type "m.login.dummy"

  @doc """
  Register for an account on this homeserver.

  Action for POST /_matrix/client/r0/register.
  """
  def register(conn, %{"auth" => %{"type" => @register_type}} = params) do
    case Register.changeset(params) do
      %Changeset{valid?: true} = cs ->
        %Register{inhibit_login: inhibit_login} = input = apply_changes(cs)

        case Account.register(input) |> Repo.transaction() do
          {:ok,
           %{
             account: %Account{localpart: localpart},
             device: %Device{device_id: device_id, access_token: access_token}
           }} ->
            data = %{user_id: MatrixServer.get_mxid(localpart)}

            data =
              if not inhibit_login do
                data
                |> Map.put(:device_id, device_id)
                |> Map.put(:access_token, access_token)
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
