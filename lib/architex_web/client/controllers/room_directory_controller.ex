defmodule ArchitexWeb.Client.RoomDirectoryController do
  use ArchitexWeb, :controller

  import ArchitexWeb.Error
  import Ecto.Query

  alias Architex.{Repo, Room, RoomServer}
  alias Plug.Conn

  @doc """
  Gets the visibility of a given room on the server's public room directory.

  Action for GET /_matrix/client/r0/directory/list/room/{roomId}.
  """
  def get_visibility(conn, %{"room_id" => room_id}) do
    case Repo.one(from r in Room, where: r.id == ^room_id) do
      %Room{visibility: visibility} ->
        conn
        |> put_status(200)
        |> json(%{visibility: visibility})

      nil ->
        put_error(conn, :not_found, "The room was not found.")
    end
  end

  @doc """
  Sets the visibility of a given room in the server's public room directory.

  Only allow the creator of the room to change visibility.
  Action for PUT /_matrix/client/r0/directory/list/room/{roomId}.
  """
  def set_visibility(%Conn{assigns: %{account: account}} = conn, %{"room_id" => room_id} = params) do
    visibility = Map.get(params, "visibility", "public")

    if visibility in ["public", "private"] do
      visibility = String.to_atom(visibility)

      with {:ok, pid} <- RoomServer.get_room_server(room_id),
           :ok <- RoomServer.set_visibility(pid, account, visibility) do
        conn
        |> send_resp(200, [])
        |> halt()
      else
        {:error, :not_found} ->
          put_error(conn, :not_found, "The given room was not found.")

        {:error, :unauthorized} ->
          put_error(conn, :unauthorized, "Only the room's creator can change visibility.")

        {:error, _} ->
          put_error(conn, :unknown)
      end
    else
      put_error(conn, :invalid_param, "Invalid visibility.")
    end
  end
end
