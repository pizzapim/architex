defmodule Architex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Architex.Repo,
      ArchitexWeb.Telemetry,
      {Phoenix.PubSub, name: Architex.PubSub},
      ArchitexWeb.Endpoint,
      {Registry, keys: :unique, name: Architex.RoomServer.Registry},
      {DynamicSupervisor, name: Architex.RoomServer.Supervisor, strategy: :one_for_one},
      Architex.KeyServer,
      {Finch, name: ArchitexWeb.HTTPClient}
    ]

    Supervisor.start_link(children, name: Architex.Supervisor, strategy: :one_for_one)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ArchitexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
