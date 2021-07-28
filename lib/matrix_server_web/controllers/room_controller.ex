defmodule MatrixServerWeb.RoomController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error
  import Ecto.Changeset

  alias MatrixServer.{Repo, Room, RoomServer}
  alias MatrixServerWeb.API.{CreateRoom}
  alias Ecto.Changeset
  alias Plug.Conn

  def create(%Conn{assigns: %{account: account}} = conn, params) do
    case CreateRoom.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input = apply_changes(cs)

        # TODO: refactor
        %Room{id: room_id} = Repo.insert!(Room.create_changeset(input))
        {:ok, pid} = RoomServer.get_room_server(room_id)
        RoomServer.create_room(pid, account, input)

        conn
        |> put_status(200)
        |> json(%{})

      _ ->
        put_error(conn, :bad_json)
    end
  end
end
