defmodule MatrixServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      MatrixServer.Repo,
      MatrixServerWeb.Telemetry,
      {Phoenix.PubSub, name: MatrixServer.PubSub},
      MatrixServerWeb.Endpoint,
      {Registry, keys: :unique, name: MatrixServer.RoomServer.Registry},
      {DynamicSupervisor, name: MatrixServer.RoomServer.Supervisor, strategy: :one_for_one},
      MatrixServer.KeyServer,
      {Finch, name: MatrixServerWeb.HTTPClient}
    ]

    Supervisor.start_link(children, name: MatrixServer.Supervisor, strategy: :one_for_one)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MatrixServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
