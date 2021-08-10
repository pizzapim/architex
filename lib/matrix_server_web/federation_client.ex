defmodule MatrixServerWeb.FederationClient do
  use Tesla

  alias MatrixServerWeb.Endpoint
  alias MatrixServerWeb.Router.Helpers, as: RouteHelpers

  # TODO: Maybe create database-backed homeserver struct to pass to client function.

  @middleware [
    Tesla.Middleware.JSON
  ]

  @adapter {Tesla.Adapter.Finch, name: MatrixServerWeb.HTTPClient}

  def client(server_name) do
    Tesla.client([{Tesla.Middleware.BaseUrl, "http://" <> server_name} | @middleware], @adapter)
  end

  def get_signing_keys(client) do
    Tesla.get(client, RouteHelpers.key_path(Endpoint, :get_signing_keys))
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

    {:ok, signature, key_id} = MatrixServer.SigningServer.sign_object(object_to_sign)
    signatures = %{origin => %{key_id => signature}}
    auth_headers = create_signature_authorization_headers(signatures, origin)

    Tesla.get(client, path, headers: auth_headers)
  end

  defp create_signature_authorization_headers(signatures, origin) do
    Enum.map(signatures[origin], fn {key, sig} ->
      {"Authorization", "X-Matrix origin=#{origin},key=\"#{key}\",sig=\"#{sig}\""}
    end)
  end
end
