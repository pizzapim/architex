# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :matrix_server,
  ecto_repos: [MatrixServer.Repo]

# Configures the endpoint
config :matrix_server, MatrixServerWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "npI0xfNYxf5FoTIdAoc7er0ZvdCJgQFZQ9LcpUFL6dsPXyQllMv45zaQQoO4ZLu1",
  render_errors: [view: MatrixServerWeb.ErrorView, accepts: ~w(json), layout: false],
  pubsub_server: MatrixServer.PubSub,
  live_view: [signing_salt: "6ymoi3Gx"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
