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
      MatrixServer.RoomServer
      # Start a worker by calling: MatrixServer.Worker.start_link(arg)
      # {MatrixServer.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MatrixServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MatrixServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
