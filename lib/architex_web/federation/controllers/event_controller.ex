defmodule ArchitexWeb.Federation.EventController do
  use ArchitexWeb, :controller
  use ArchitexWeb.Federation.AuthenticateServer

  import ArchitexWeb.Error
  import Ecto.Query

  alias Architex.{Repo, Event, RoomServer}
  alias ArchitexWeb.Federation.Transaction

  @doc """
  Retrieves a single event.

  Action for GET /_matrix/federation/v1/event/{eventId}.
  """
  def event(%Plug.Conn{assigns: %{origin: origin}} = conn, %{"event_id" => event_id}) do
    query =
      Event
      |> where([e], e.id == ^event_id)
      |> preload(:room)

    case Repo.one(query) do
      %Event{room: room} = event ->
        case RoomServer.get_room_server(room) do
          {:ok, pid} ->
            if RoomServer.server_in_room?(pid, origin) do
              data = Transaction.new([event])

              conn
              |> put_status(200)
              |> json(data)
            else
              put_error(conn, :unauthorized, "Origin server is not participating in room.")
            end

          _ ->
            put_error(conn, :unknown)
        end

      nil ->
        put_error(conn, :not_found, "Event or room not found.")
    end
  end

  def event(conn, _), do: put_error(conn, :missing_param)

  @doc """
  Retrieves a snapshot of a room's state at a given event.

  Action for GET /_matrix/federation/v1/state/{roomId}.
  """
  def state(%Plug.Conn{assigns: %{origin: origin}} = conn, %{
        "event_id" => event_id,
        "room_id" => room_id
      }) do
    get_state_or_state_ids(conn, :state, origin, event_id, room_id)
  end

  def state(conn, _), do: put_error(conn, :missing_param)

  @doc """
  Retrieves a snapshot of a room's state at a given event, in the form of event IDs.

  Action for GET /_matrix/federation/v1/state_ids/{roomId}.
  """
  def state_ids(%Plug.Conn{assigns: %{origin: origin}} = conn, %{
        "event_id" => event_id,
        "room_id" => room_id
      }) do
    get_state_or_state_ids(conn, :state_ids, origin, event_id, room_id)
  end

  def state_ids(conn, _), do: put_error(conn, :missing_param)

  @spec get_state_or_state_ids(
          Plug.Conn.t(),
          :state | :state_ids,
          String.t(),
          String.t(),
          String.t()
        ) :: Plug.Conn.t()
  defp get_state_or_state_ids(conn, state_or_state_ids, origin, event_id, room_id) do
    query =
      Event
      |> where([e], e.id == ^event_id and e.room_id == ^room_id)
      |> preload(:room)

    case Repo.one(query) do
      %Event{room: room} = event ->
        case RoomServer.get_room_server(room) do
          {:ok, pid} ->
            if RoomServer.server_in_room?(pid, origin) do
              # {state_events, auth_chain} =
              data =
                case state_or_state_ids do
                  :state ->
                    {state_events, auth_chain} = RoomServer.get_state_at_event(pid, event)

                    %{
                      auth_chain: Enum.map(auth_chain, &Architex.Event.Formatters.as_pdu/1),
                      pdus: Enum.map(state_events, &Architex.Event.Formatters.as_pdu/1)
                    }

                  :state_ids ->
                    {state_event_ids, auth_chain_ids} =
                      RoomServer.get_state_ids_at_event(pid, event)

                    %{auth_chain: auth_chain_ids, pdus: state_event_ids}
                end

              conn
              |> put_status(200)
              |> json(data)
            else
              put_error(conn, :unauthorized, "Origin server is not participating in room.")
            end

          _ ->
            put_error(conn, :unknown)
        end

      nil ->
        put_error(conn, :not_found, "Event or room not found.")
    end
  end
end
