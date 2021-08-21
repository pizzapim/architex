defmodule MatrixServerWeb.Federation.EventController do
  use MatrixServerWeb, :controller
  use MatrixServerWeb.Federation.AuthenticateServer

  import MatrixServerWeb.Error
  import Ecto.Query

  alias MatrixServer.{Repo, Event, RoomServer}
  alias MatrixServerWeb.Federation.Transaction

  def event(%Plug.Conn{assigns: %{origin: origin}} = conn, %{"event_id" => event_id}) do
    query =
      Event
      |> where([e], e.event_id == ^event_id)
      |> preload(:room)

    case Repo.one(query) do
      %Event{room: room} = event ->
        case RoomServer.get_room_server(room) do
          {:ok, pid} ->
            if RoomServer.server_in_room(pid, origin) do
              data = Transaction.new([event])

              conn
              |> put_status(200)
              |> json(data)
            else
              put_error(
                conn,
                :unauthorized,
                "Origin server is not allowed to see requested event."
              )
            end

          _ ->
            put_error(conn, :unknown)
        end

      nil ->
        put_error(conn, :not_found, "Event or room not found.")
    end
  end

  def event(conn, _), do: put_error(conn, :bad_json)
end
