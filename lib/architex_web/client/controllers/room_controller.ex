defmodule ArchitexWeb.Client.RoomController do
  use ArchitexWeb, :controller

  import ArchitexWeb.Error
  import Ecto.Query

  alias Architex.{Repo, Room, RoomServer, Event}
  alias Architex.Types.UserId
  alias ArchitexWeb.Client.Request.{CreateRoom, Kick, Ban, Messages}
  alias Plug.Conn

  @doc """
  Create a new room with various configuration options.

  Action for POST /_matrix/client/r0/createRoom.
  """
  def create(%Conn{assigns: %{account: account}} = conn, params) do
    with {:ok, request} <- CreateRoom.parse(params) do
      case Room.create(account, request) do
        {:ok, room_id} ->
          conn
          |> put_status(200)
          |> json(%{room_id: room_id})

        {:error, :authorization} ->
          put_error(conn, :invalid_room_state)

        {:error, :alias} ->
          put_error(conn, :room_in_use, "The requested alias is already in use.")

        {:error, :unknown} ->
          put_error(conn, :unknown)
      end
    else
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

    conn
    |> put_status(200)
    |> json(%{joined_rooms: joined_room_ids})
  end

  @doc """
  This API invites a user to participate in a particular room.

  Action for POST /_matrix/client/r0/rooms/{roomId}/invite.
  """
  def invite(%Conn{assigns: %{account: account}} = conn, %{
        "room_id" => room_id,
        "user_id" => user_id
      }) do
    with {:ok, user_id_struct} <- UserId.cast(user_id),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      {avatar_url, displayname} = UserId.try_get_user_information(user_id_struct)

      case RoomServer.invite(pid, account, user_id, avatar_url, displayname) do
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
    with {:ok, %Kick{user_id: user_id} = request} <- Kick.parse(params),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      {avatar_url, displayname} = UserId.try_get_user_information(user_id)

      case RoomServer.kick(pid, account, request, avatar_url, displayname) do
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

  @doc """
  Ban a user in the room.

  Action for POST /_matrix/client/r0/rooms/{roomId}/ban.
  """
  def ban(%Conn{assigns: %{account: account}} = conn, %{"room_id" => room_id} = params) do
    with {:ok, %Ban{user_id: user_id} = request} <- Ban.parse(params),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      {avatar_url, displayname} = UserId.try_get_user_information(user_id)

      case RoomServer.ban(pid, account, request, avatar_url, displayname) do
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

  @doc """
  Unban a user from the room.

  Action for POST /_matrix/client/r0/rooms/{roomId}/unban.
  """
  def unban(%Conn{assigns: %{account: account}} = conn, %{
        "room_id" => room_id,
        "user_id" => user_id
      }) do
    with {:ok, user_id_struct} <- UserId.cast(user_id),
         {:ok, pid} <- RoomServer.get_room_server(room_id) do
      {avatar_url, displayname} = UserId.try_get_user_information(user_id_struct)

      case RoomServer.unban(pid, account, user_id, avatar_url, displayname) do
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

  def unban(conn, _), do: put_error(conn, :missing_param)

  @doc """
  This endpoint is used to send a message event to a room.

  Action for PUT /_matrix/client/r0/rooms/{roomId}/send/{eventType}/{txnId}.
  """
  def send_message_event(
        %Conn{assigns: %{account: account, device: device}, body_params: body_params} = conn,
        %{
          "room_id" => room_id,
          "event_type" => event_type,
          "txn_id" => txn_id
        }
      ) do
    case RoomServer.get_room_server(room_id) do
      {:ok, pid} ->
        case RoomServer.send_message_event(pid, account, device, event_type, body_params, txn_id) do
          {:ok, event_id} ->
            conn
            |> put_status(200)
            |> json(%{event_id: event_id})

          {:error, _} ->
            put_error(conn, :unknown)
        end

      {:error, :not_found} ->
        put_error(conn, :not_found, "The given room was not found.")
    end
  end

  @doc """
  State events can be sent using this endpoint.

  I don't know why, but the spec is very scared of trailing slashes and accidentally
  using a transaction ID as the state key.
  I take no precaution against these things, it's the responsibility of the client.
  Action for PUT /_matrix/client/r0/rooms/{roomId}/state/{eventType}/{stateKey}.
  """
  def send_state_event(conn, %{"state_key" => [state_key | _]} = params) do
    do_send_state_event(conn, params, state_key)
  end

  def send_state_event(conn, params) do
    do_send_state_event(conn, params, "")
  end

  defp do_send_state_event(
         %Conn{assigns: %{account: account}, body_params: body_params} = conn,
         %{"room_id" => room_id, "event_type" => event_type},
         state_key
       ) do
    # TODO: Check aliases according to spec.
    case RoomServer.get_room_server(room_id) do
      {:ok, pid} ->
        case RoomServer.send_state_event(pid, account, event_type, body_params, state_key) do
          {:ok, event_id} ->
            conn
            |> put_status(200)
            |> json(%{event_id: event_id})

          {:error, _} ->
            put_error(conn, :unknown)
        end

      {:error, :not_found} ->
        put_error(conn, :not_found, "The given room was not found.")
    end
  end

  @doc """
  This API returns a list of message and state events for a room.

  Action for GET /_matrix/client/r0/rooms/{roomId}/messages.
  """
  def messages(%Conn{assigns: %{account: account}} = conn, %{"room_id" => room_id} = params) do
    with {:ok, request} <- Messages.parse(params) do
      room_query =
        account
        |> Ecto.assoc(:joined_rooms)
        |> where([r], r.id == ^room_id)

      case Repo.one(room_query) do
        %Room{} = room ->
          {events, start, end_} = Room.get_messages(room, request)
          events = Enum.map(events, &Event.Formatters.messages_response/1)
          data = %{chunk: events}
          data = if start, do: Map.put(data, :start, Integer.to_string(start)), else: data
          data = if end_, do: Map.put(data, :end, Integer.to_string(end_)), else: data

          conn
          |> put_status(200)
          |> json(data)

        nil ->
          put_error(conn, :forbidden, "You are not participating in this room.")
      end
    else
      {:error, _} -> put_error(conn, :bad_json)
    end
  end

  @doc """
  Get the state events for the current state of a room.

  Action for GET /_matrix/client/r0/rooms/{roomId}/state.
  """
  def get_state(%Conn{assigns: %{account: account}} = conn, %{"room_id" => room_id}) do
    case RoomServer.get_room_server(room_id) do
      {:ok, pid} ->
        case RoomServer.get_current_state(pid, account) do
          {:ok, events} ->
            events = Enum.map(events, &Event.Formatters.state_response/1)

            conn
            |> put_status(200)
            |> json(events)

          :error ->
            put_error(
              conn,
              :forbidden,
              "You aren't a member of the room and weren't previously a member of the room."
            )
        end

      {:error, :not_found} ->
        put_error(conn, :not_found, "The given room was not found.")
    end
  end

  @doc """
  Looks up the contents of a state event in a room.

  Action for GET /_matrix/client/r0/rooms/{roomId}/state/{eventType}/{stateKey}.
  """
  def get_state_event(conn, %{"state_key" => [state_key | _]} = params) do
    do_get_state_event(conn, params, state_key)
  end

  def get_state_event(conn, params) do
    do_get_state_event(conn, params, "")
  end

  defp do_get_state_event(
         %Conn{assigns: %{account: account}} = conn,
         %{"room_id" => room_id, "event_type" => event_type},
         state_key
       ) do
    case RoomServer.get_room_server(room_id) do
      {:ok, pid} ->
        case RoomServer.get_state_event(pid, account, event_type, state_key) do
          {:ok, content} ->
            conn
            |> put_status(200)
            |> json(content)

          {:error, :unauthorized} ->
            put_error(
              conn,
              :forbidden,
              "You aren't a member of the room and weren't previously a member of the room."
            )

          {:error, :not_found} ->
            put_error(conn, :not_found, "The room has no state with the given type or key.")
        end

      {:error, :not_found} ->
        put_error(conn, :not_found, "The given room was not found.")
    end
  end
end
