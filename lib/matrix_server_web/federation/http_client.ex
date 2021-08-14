defmodule MatrixServerWeb.Federation.HTTPClient do
  use Tesla

  alias MatrixServerWeb.Endpoint
  alias MatrixServerWeb.Federation.Request.GetSigningKeys
  alias MatrixServerWeb.Federation.Middleware.SignRequest
  alias MatrixServerWeb.Router.Helpers, as: RouteHelpers

  # TODO: Maybe create database-backed homeserver struct to pass to client function.
  # TODO: Fix error propagation.

  @adapter {Tesla.Adapter.Finch, name: MatrixServerWeb.HTTPClient}

  def client(server_name) do
    Tesla.client(
      [
        {Tesla.Middleware.Opts, [server_name: server_name]},
        SignRequest,
        {Tesla.Middleware.BaseUrl, "http://" <> server_name},
        Tesla.Middleware.JSON
      ],
      @adapter
    )
  end

  def get_signing_keys(client) do
    path = RouteHelpers.key_path(Endpoint, :get_signing_keys)

    with {:ok,
          %GetSigningKeys{server_name: server_name, verify_keys: verify_keys, signatures: sigs} =
            response} <- tesla_request(:get, client, path, GetSigningKeys),
         {:ok, encoded_body} <- MatrixServer.serialize_and_encode(response),
         server_sigs when not is_nil(server_sigs) <- sigs[server_name] do
      # For each verify key, check if there is a matching signature.
      # If not, invalidate the whole response.
      Enum.all?(verify_keys, fn {key_id, %{"key" => key}} ->
        with true <- Map.has_key?(server_sigs, key_id),
             {:ok, decoded_key} <- MatrixServer.decode_base64(key),
             {:ok, decoded_sig} <- MatrixServer.decode_base64(server_sigs[key_id]) do
          MatrixServer.sign_verify(decoded_sig, encoded_body, decoded_key)
        else
          _ -> false
        end
      end)
      |> then(fn
        true -> {:ok, response}
        false -> :error
      end)
    else
      _ -> :error
    end
  end

  def query_profile(client, user_id, field \\ nil) do
    path = RouteHelpers.query_path(Endpoint, :profile) |> Tesla.build_url(user_id: user_id)
    path = if field, do: Tesla.build_url(path, field: field), else: path

    Tesla.get(client, path)
  end

  defp tesla_request(method, client, path, request_schema) do
    with {:ok, %Tesla.Env{body: body}} <- Tesla.request(client, url: path, method: method),
         %Ecto.Changeset{valid?: true} = cs <- apply(request_schema, :changeset, [body]) do
      {:ok, Ecto.Changeset.apply_changes(cs)}
    else
      _ -> :error
    end
  end
end
