defmodule MatrixServerWeb.RoomController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error
  import Ecto.Changeset

  alias MatrixServerWeb.API.{CreateRoom}
  alias Ecto.Changeset

  def create(conn, params) do
    case CreateRoom.changeset(params) do
      %Changeset{valid?: true} = cs ->
        api_struct = apply_changes(cs)

        MatrixServer.RoomServer.create_room(api_struct)

        conn
        |> put_status(200)
        |> json(%{})

      _ ->
        put_error(conn, :bad_json)
    end
  end
end
