defmodule ArchitexWeb.Client.SyncController do
  use ArchitexWeb, :controller

  import ArchitexWeb.Error
  import Ecto.Query

  alias Architex.{Repo, Event, Account, Room, JoinedRoom}
  alias Plug.Conn

  @doc """
  Synchronise the client's state with the latest state on the server.

  Parameters: %{"filter" => "{\"account_data\":{},\"presence\":{},\"room\":{\"account_data\":{},\"ephemeral\":{},\"state\":{\"lazy_load_members\":true},\"timeline\":{\"limit\":100}}}", "path" => ["_matrix", "client", "r0", "sync"], "timeout" => "30000"}
  Action for GET /_matrix/client/r0/sync.
  """
  # When no "since" is specified, return the most recent messages.
  def sync(%Conn{assigns: %{account: %Account{id: account_id}}} = conn, params)
      when not is_map_key(params, "since") do
    # joined_rooms =
    #   account
    #   |> Ecto.assoc(:joined_rooms)
    #   |> Repo.all()
    #   |> Enum.into(%{}, fn %Room{id: room_id} = room ->
    #     {room_id, room}
    #   end)

    events_per_room =
      Event
      |> join(:inner, [e], jr in JoinedRoom,
        on: jr.room_id == e.room_id and jr.account_id == ^account_id
      )
      |> join(:inner, [e, jr], r in Room, on: r.id == jr.room_id)
      |> order_by(asc: :origin_server_ts, asc: :nid)
      |> Repo.all()
      |> Enum.group_by(& &1.room_id)

    join =
      Enum.into(events_per_room, %{}, fn {room_id, [%Event{nid: first_nid} | _] = events} ->
        joined_room = %{
          timeline: %{
            events: Enum.map(events, &Event.Formatters.sync_response/1),
            limited: false,
            prev_batch: Integer.to_string(first_nid)
          }
        }

        {room_id, joined_room}
      end)

    next_batch = Enum.map(events_per_room, fn {_, events} ->
      %Event{nid: last_nid} = List.last(events)
      last_nid
    end)
    |> Enum.max(fn -> 0 end)

    data = %{
      next_batch: Integer.to_string(next_batch),
      rooms: %{
        join: join,
        invite: %{},
        leave: %{}
      }
    }

    conn
    |> put_status(200)
    |> json(data)
  end

  # TODO: Long-poll for new incoming events.
  # Should think about how to implement this in a nice way.
  def sync(conn, _params), do: put_error(conn, :unknown, "Not implemented yet.")
end
