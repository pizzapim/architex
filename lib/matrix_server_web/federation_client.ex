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

  def test_server_auth(client) do
    origin = "localhost:4001"
    destination = "localhost:4000"
    path = RouteHelpers.test_path(Endpoint, :test)

    params = %{
      method: "POST",
      uri: path,
      origin: origin,
      destination: destination,
      content: %{"hi" => "hello"}
    }

    {:ok, signed_object} = MatrixServer.SigningServer.sign_object(params)
    auth_headers = create_signature_authorization_headers(signed_object, origin)

    Tesla.post(client, path, signed_object, headers: auth_headers)
  end

  defp create_signature_authorization_headers(%{signatures: signatures}, origin) do
    Enum.map(signatures[origin], fn {key, sig} ->
      {"Authorization", "X-Matrix origin=#{origin},key=\"#{key}\",sig=\"#{sig}\""}
    end)
  end
end
