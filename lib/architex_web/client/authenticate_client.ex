defmodule ArchitexWeb.Client.Plug.AuthenticateClient do
  import ArchitexWeb.Error
  import Plug.Conn

  alias Architex.Account
  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{params: %{"access_token" => access_token}} = conn, _opts) do
    authenticate(conn, access_token)
  end

  def call(%Conn{req_headers: headers} = conn, _opts) do
    case List.keyfind(headers, "authorization", 0) do
      {_, "Bearer " <> access_token} ->
        authenticate(conn, access_token)

      _ ->
        put_error(conn, :missing_token)
    end
  end

  defp authenticate(conn, access_token) do
    case Account.by_access_token(access_token) do
      {account, device} ->
        conn
        |> assign(:account, account)
        |> assign(:device, device)

      nil ->
        put_error(conn, :unknown_token)
    end
  end
end
