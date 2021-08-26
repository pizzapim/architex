defmodule MatrixServerWeb.Client.RoomController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Error
  import Ecto.{Changeset, Query}

  alias MatrixServer.{Repo, Room, RoomServer}
  alias MatrixServer.Types.UserId
  alias MatrixServerWeb.Client.Request.{CreateRoom, Kick}
  alias Ecto.Changeset
  alias Plug.Conn

  @doc """
  Create a new room with various configuration options.

  Action for POST /_matrix/client/r0/createRoom.
  """
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

  @doc """
  This API returns a list of the user's current rooms.

  Action for GET /_matrix/client/r0/joined_rooms.
  """
  def joined_rooms(%Conn{assigns: %{account: account}} = conn, _params) do
    joined_room_ids =
      account
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

  @doc """
  This API invites a user to participate in a particular room.

  Action for POST /_matrix/client/r0/rooms/{roomId}/invite.
  """
  def invite(%Conn{assigns: %{account: account}} = conn, %{
        "room_id" => room_id,
        "user_id" => user_id
      }) do
    with {:ok, _} <- UserId.cast(user_id),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      case RoomServer.invite(pid, account, user_id) do
        :ok ->
          conn
          |> send_resp(200, [])
          |> halt()

        {:error, _} ->
          put_error(conn, :unknown)
      end
    else
      :error -> put_error(conn, :invalid_param, "Given user ID is invalid.")
      {:error, :not_found} -> put_error(conn, :not_found, "The given room was not found.")
    end
  end

  def invite(conn, _), do: put_error(conn, :missing_param)

  @doc """
  This API starts a user participating in a particular room, if that user is allowed to participate in that room.

  Action for POST /_matrix/client/r0/rooms/{roomId}/join.
  TODO: third_party_signed
  """
  def join(%Conn{assigns: %{account: account}} = conn, %{"room_id" => room_id}) do
    case RoomServer.get_room_server(room_id) do
      {:ok, pid} ->
        case RoomServer.join(pid, account) do
          {:ok, room_id} ->
            conn
            |> put_status(200)
            |> json(%{room_id: room_id})

          {:error, _} ->
            put_error(conn, :unknown)
        end

      {:error, :not_found} ->
        put_error(conn, :not_found, "The given room was not found.")
    end
  end

  @doc """
  This API stops a user participating in a particular room.

  Action for POST /_matrix/client/r0/rooms/{roomId}/leave.
  """
  def leave(%Conn{assigns: %{account: account}} = conn, %{"room_id" => room_id}) do
    case RoomServer.get_room_server(room_id) do
      {:ok, pid} ->
        case RoomServer.leave(pid, account) do
          :ok ->
            conn
            |> send_resp(200, [])
            |> halt()

          {:error, _} ->
            put_error(conn, :unknown)
        end

      {:error, :not_found} ->
        put_error(conn, :not_found, "The given room was not found.")
    end
  end

  @doc """
  Kick a user from the room.

  Action for POST /_matrix/client/r0/rooms/{roomId}/kick.
  """
  def kick(%Conn{assigns: %{account: account}} = conn, %{"room_id" => room_id} = params) do
    with {:ok, request} <- Kick.parse(params),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      case RoomServer.kick(pid, account, request) do
        :ok ->
          conn
          |> send_resp(200, [])
          |> halt()

        {:error, _} ->
          put_error(conn, :unknown)
      end
    else
      {:error, %Ecto.Changeset{}} -> put_error(conn, :bad_json)
      {:error, :not_found} -> put_error(conn, :not_found, "Room not found.")
    end
  end
end
