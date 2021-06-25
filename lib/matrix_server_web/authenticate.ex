defmodule MatrixServerWeb.Authenticate do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias MatrixServer.Account
  alias Plug.Conn

  def init(options), do: options

  def call(%Conn{params: %{"access_token" => access_token}} = conn, _opts) do
    authenticate(conn, access_token)
  end

  def call(%Conn{req_headers: headers} = conn, _opts) do
    case List.keyfind(headers, "authorization", 0) do
      {_, "Bearer " <> access_token} ->
        authenticate(conn, access_token)

      _ ->
        data = %{errcode: "M_MISSING_TOKEN", error: "Access token missing."}

        conn
        |> put_status(401)
        |> json(data)
        |> halt()
    end
  end

  defp authenticate(conn, access_token) do
    case Account.get_by_access_token(access_token) do
      %Account{devices: [device]} = account ->
        conn
        |> assign(:account, account)
        |> assign(:device, device)

      nil ->
        data = %{errcode: "M_UNKNOWN_TOKEN", error: "Invalid access token."}

        conn
        |> put_status(401)
        |> json(data)
        |> halt()
    end
  end
end
