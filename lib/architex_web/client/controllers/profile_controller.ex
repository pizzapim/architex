defmodule ArchitexWeb.Client.ProfileController do
  # TODO: Changes should be propagated using join events and presence.
  use ArchitexWeb, :controller

  import ArchitexWeb.Error
  import Ecto.Query

  alias Architex.{Repo, Account}
  alias Architex.Types.UserId
  alias ArchitexWeb.Federation.HTTPClient
  alias Plug.Conn
  alias Ecto.Changeset

  @doc """
  Get the combined profile information for this user.

  Action for GET /_matrix/client/r0/profile/{userId}.
  """
  def profile(conn, %{"user_id" => user_id}) do
    case UserId.cast(user_id) do
      {:ok, %UserId{localpart: localpart, domain: domain}} ->
        if domain == Architex.server_name() do
          case Repo.one(from a in Account, where: a.localpart == ^localpart) do
            %Account{displayname: displayname, avatar_url: avatar_url} ->
              data = %{}
              data = if avatar_url, do: Map.put(data, :avatar_url, avatar_url), else: data
              data = if displayname, do: Map.put(data, :displayname, displayname), else: data

              conn
              |> put_status(200)
              |> json(data)

            nil ->
              put_error(conn, :not_found, "User was not found.")
          end
        else
          case HTTPClient.client(domain) |> HTTPClient.query_profile(user_id) do
            {:ok, response} ->
              conn
              |> put_status(200)
              |> json(response)

            {:error, _, _} ->
              put_error(conn, :not_found, "User was not found.")
          end
        end

      :error ->
        put_error(conn, :not_found, "User ID is invalid.")
    end
  end

  @doc """
  Get the user's display name.

  Action for GET /_matrix/client/r0/profile/{userId}/displayname.
  """
  def get_displayname(conn, %{"user_id" => user_id}) do
    get_property(conn, :displayname, user_id)
  end

  @doc """
  Get the user's avatar URL.

  Action for GET /_matrix/client/r0/profile/{userId}/avatar_url.
  """
  def get_avatar_url(conn, %{"user_id" => user_id}) do
    get_property(conn, :avatar_url, user_id)
  end

  defp get_property(conn, property_key, user_id) do
    case UserId.cast(user_id) do
      {:ok, %UserId{localpart: localpart, domain: domain}} ->
        if domain == Architex.server_name() do
          case Repo.one(from a in Account, where: a.localpart == ^localpart) do
            %Account{} = account ->
              property_val = Map.get(account, property_key)
              data = if property_val, do: %{property_key => property_val}, else: %{}

              conn
              |> put_status(200)
              |> json(data)

            nil ->
              put_error(conn, :not_found, "User was not found.")
          end
        else
          case HTTPClient.client(domain)
               |> HTTPClient.query_profile(user_id, Atom.to_string(property_key)) do
            {:ok, response} ->
              conn
              |> put_status(200)
              |> json(response)

            {:error, _, _} ->
              put_error(conn, :not_found, "User was not found.")
          end
        end

      :error ->
        put_error(conn, :not_found, "User ID is invalid.")
    end
  end

  @doc """
  This API sets the given user's display name.

  Action for PUT /_matrix/client/r0/profile/{userId}/displayname.
  """
  def set_displayname(conn, %{"user_id" => user_id} = params) do
    displayname = Map.get(params, "displayname")

    update_property(conn, :displayname, displayname, user_id)
  end

  @doc """
  This API sets the given user's avatar URL.

  Action for PUT /_matrix/client/r0/profile/{userId}/avatar_url.
  """
  def set_avatar_url(conn, %{"user_id" => user_id} = params) do
    avatar_url = Map.get(params, "avatar_url")

    update_property(conn, :avatar_url, avatar_url, user_id)
  end

  defp update_property(
         %Conn{assigns: %{account: account}} = conn,
         property_key,
         property,
         user_id
       ) do
    if Account.get_mxid(account) == user_id do
      account
      |> Changeset.change([{property_key, property}])
      |> Repo.update()

      conn
      |> send_resp(200, [])
      |> halt()
    else
      put_error(conn, :unauthorized, "User ID does not match access token.")
    end
  end
end
