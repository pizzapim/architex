defmodule MatrixServerWeb.Federation.KeyController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error

  alias MatrixServer.KeyServer

  @key_valid_time_ms 1000 * 60 * 24 * 30

  def get_signing_keys(conn, _params) do
    keys =
      KeyServer.get_own_signing_keys()
      |> Enum.into(%{}, fn {key_id, key} ->
        {key_id, %{"key" => key}}
      end)

    data = %{
      server_name: MatrixServer.server_name(),
      verify_keys: keys,
      old_verify_keys: %{},
      valid_until_ts: System.os_time(:millisecond) + @key_valid_time_ms
    }

    case KeyServer.sign_object(data) do
      {:ok, sig, key_id} ->
        signed_data = MatrixServer.add_signature(data, key_id, sig)

        conn
        |> put_status(200)
        |> json(signed_data)

      :error ->
        put_error(conn, :unknown, "Error signing object.")
    end
  end
end
