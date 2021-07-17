defmodule MatrixServerWeb.RoomController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error
  import Ecto.Changeset

  alias MatrixServerWeb.API.{CreateRoom}
  alias Ecto.Changeset
  alias Plug.Conn

  def create(%Conn{assigns: %{account: account}} = conn, params) do
    case CreateRoom.changeset(params) do
      %Changeset{valid?: true} = cs ->
        cs
        |> apply_changes()
        |> MatrixServer.RoomServer.create_room(account)

        conn
        |> put_status(200)
        |> json(%{})

      _ ->
        put_error(conn, :bad_json)
    end
  end
end
