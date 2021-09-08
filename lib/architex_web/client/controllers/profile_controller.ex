defmodule ArchitexWeb.Client.ProfileController do
  use ArchitexWeb, :controller

  import ArchitexWeb.Error
  import Ecto.Query

  alias Architex.{Repo, Account}
  alias Architex.Types.UserId
  alias Plug.Conn
  alias Ecto.Changeset

  @doc """
  Get the user's avatar URL.

  Action for GET /_matrix/client/r0/profile/{userId}/avatar_url.
  """
  def get_avatar_url(conn, %{"user_id" => user_id}) do
    case UserId.cast(user_id) do
      {:ok, %UserId{localpart: localpart, domain: domain}} ->
        if domain == Architex.server_name() do
          case Repo.one(from a in Account, where: a.localpart == ^localpart) do
            %Account{avatar_url: avatar_url} ->
              data = if avatar_url, do: %{avatar_url: avatar_url}, else: %{}

              conn
              |> put_status(200)
              |> json(data)

            nil ->
              put_error(conn, :not_found, "User was not found.")
          end
        else
          # TODO: Use federation to lookup avatar URL.
          put_error(conn, :not_found, "User was not found.")
        end

      :error ->
        put_error(conn, :not_found, "User ID is invalid.")
    end
  end

  @doc """
  This API sets the given user's avatar URL.

  Action for PUT /_matrix/client/r0/profile/{userId}/avatar_url.
  """
  def set_avatar_url(%Conn{assigns: %{account: account}} = conn, %{"user_id" => user_id} = params) do
    if Account.get_mxid(account) == user_id do
      avatar_url = Map.get(params, "avatar_url")

      if not is_nil(avatar_url) do
        account
        |> Changeset.change(avatar_url: avatar_url)
        |> Repo.update()
      end

      conn
      |> send_resp(200, [])
      |> halt()
    else
      put_error(conn, :unauthorized, "User ID does not match access token.")
    end
  end
end
