defmodule MatrixServerWeb.FederationClient do
  use Tesla

  alias MatrixServerWeb.Endpoint
  alias MatrixServerWeb.Federation.Request.GetSigningKeys
  alias MatrixServerWeb.Router.Helpers, as: RouteHelpers

  # TODO: Maybe create database-backed homeserver struct to pass to client function.

  @middleware [
    Tesla.Middleware.JSON
  ]

  @adapter {Tesla.Adapter.Finch, name: MatrixServerWeb.HTTPClient}

  def client(server_name) do
    Tesla.client([{Tesla.Middleware.BaseUrl, "http://" <> server_name} | @middleware], @adapter)
  end

  @path RouteHelpers.key_path(Endpoint, :get_signing_keys)
  def get_signing_keys(client) do
    # TODO: Which server_name should we take?
    # TODO: Should probably catch enacl exceptions and just return error atom,
    #       create seperate function for this.
    with {:ok,
          %GetSigningKeys{server_name: server_name, verify_keys: verify_keys, signatures: sigs} =
            response} <- tesla_request(:get, client, @path, GetSigningKeys),
         {:ok, encoded_body} <- MatrixServer.serialize_and_encode(response) do
      # For each verify key, check if there is a matching signature.
      # If not, invalidate the whole response.
      if Map.has_key?(sigs, server_name) do
        server_sigs = sigs[server_name]

        all_keys_signed? =
          Enum.all?(verify_keys, fn {key_id, %{"key" => key}} ->
            with true <- Map.has_key?(server_sigs, key_id),
                 {:ok, decoded_key} <- MatrixServer.decode_base64(key),
                 {:ok, decoded_sig} <- MatrixServer.decode_base64(server_sigs[key_id]) do
              :enacl.sign_verify_detached(decoded_sig, encoded_body, decoded_key)
            else
              _ -> false
            end
          end)

        if all_keys_signed? do
          {:ok, response}
        else
          :error
        end
      else
        :error
      end
    end
  end

  # TODO: Create tesla middleware to add signature and headers.
  def query_profile(client, server_name, user_id, field \\ nil) do
    origin = MatrixServer.server_name()
    path = RouteHelpers.query_path(Endpoint, :profile) |> Tesla.build_url(user_id: user_id)
    path = if field, do: Tesla.build_url(path, field: field), else: path

    object_to_sign = %{
      method: "GET",
      uri: path,
      origin: origin,
      destination: server_name
    }

    {:ok, signature, key_id} = MatrixServer.KeyServer.sign_object(object_to_sign)
    signatures = %{origin => %{key_id => signature}}
    auth_headers = create_signature_authorization_headers(signatures, origin)

    Tesla.get(client, path, headers: auth_headers)
  end

  defp create_signature_authorization_headers(signatures, origin) do
    Enum.map(signatures[origin], fn {key, sig} ->
      {"Authorization", "X-Matrix origin=#{origin},key=\"#{key}\",sig=\"#{sig}\""}
    end)
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
