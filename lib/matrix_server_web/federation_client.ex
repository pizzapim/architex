defmodule MatrixServerWeb.FederationClient do
  use Tesla

  alias MatrixServerWeb.Endpoint
  alias MatrixServerWeb.Router.Helpers, as: RouteHelpers

  # TODO: Maybe create database-backed homeserver struct to pass to client function.

  @middleware [
    {Tesla.Middleware.Headers, [{"Content-Type", "application/json"}]},
    Tesla.Middleware.JSON
  ]

  @adapter {Tesla.Adapter.Finch, name: MatrixServerWeb.HTTPClient}

  def client(server_name) do
    Tesla.client([{Tesla.Middleware.BaseUrl, server_name} | @middleware], @adapter)
  end

  def get_signing_keys(client) do
    Tesla.get(client, RouteHelpers.key_path(Endpoint, :get_signing_keys))
  end
end
