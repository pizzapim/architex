defmodule MatrixServerWeb.Client.RoomController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Error
  import Ecto.{Changeset, Query}

  alias MatrixServer.{Repo, Room}
  alias MatrixServerWeb.Client.Request.CreateRoom
  alias Ecto.Changeset
  alias Plug.Conn

  def create(%Conn{assigns: %{account: account}} = conn, params) do
    case CreateRoom.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input = apply_changes(cs)

        case Room.create(account, input) do
          {:ok, room_id} ->
            conn
            |> put_status(200)
            |> json(%{room_id: room_id})

          {:error, :authorization} ->
            put_error(conn, :invalid_room_state)

          {:error, :unknown} ->
            put_error(conn, :unknown)
        end

      _ ->
        put_error(conn, :bad_json)
    end
  end

  def joined_rooms(%Conn{assigns: %{account: account}} = conn, _params) do
    joined_room_ids = account
    |> Ecto.assoc(:joined_rooms)
    |> select([jr], jr.id)
    |> Repo.all()

    data = %{
      joined_rooms: joined_room_ids
    }

    conn
    |> put_status(200)
    |> json(data)
  end
end
