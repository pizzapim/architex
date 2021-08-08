defmodule MatrixServerWeb.Federation.KeyController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error

  alias MatrixServer.SigningServer

  @key_valid_time_ms 1000 * 60 * 24 * 30

  def get_signing_keys(conn, _params) do
    keys =
      SigningServer.get_signing_keys(true)
      |> Enum.into(%{}, fn {key_id, key} ->
        {key_id, %{"key" => key}}
      end)

    data = %{
      server_name: MatrixServer.server_name(),
      verify_keys: keys,
      old_verify_keys: %{},
      valid_until_ts: System.os_time(:millisecond) + @key_valid_time_ms
    }

    case SigningServer.sign_object(data) do
      {:ok, signed_data} ->
        conn
        |> put_status(200)
        |> json(signed_data)

      {:error, _msg} ->
        put_error(conn, :unknown, "Error signing object.")
    end
  end
end
