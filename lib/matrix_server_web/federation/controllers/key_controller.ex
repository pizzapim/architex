defmodule MatrixServerWeb.Federation.KeyController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Error

  alias MatrixServer.KeyServer

  @doc """
  Gets the homeserver's published signing keys.

  Action for GET /_matrix/key/v2/server/{keyId}.
  """
  def get_signing_keys(conn, _params) do
    keys =
      KeyServer.get_own_signing_keys()
      |> Enum.into(%{}, fn {key_id, key} ->
        {key_id, %{"key" => key}}
      end)

    # TODO: Consider using TimeX.
    # Valid for one month.
    valid_until = DateTime.utc_now() |> DateTime.add(60 * 60 * 24 * 30, :second)

    data = %{
      server_name: MatrixServer.server_name(),
      verify_keys: keys,
      old_verify_keys: %{},
      valid_until_ts: DateTime.to_unix(valid_until, :millisecond)
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
