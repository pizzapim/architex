# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :architex,
  ecto_repos: [Architex.Repo]

# Configures the endpoint
config :architex, ArchitexWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "npI0xfNYxf5FoTIdAoc7er0ZvdCJgQFZQ9LcpUFL6dsPXyQllMv45zaQQoO4ZLu1",
  render_errors: [view: ArchitexWeb.ErrorView, accepts: ~w(json), layout: false],
  pubsub_server: Architex.PubSub,
  live_view: [signing_salt: "6ymoi3Gx"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :architex, Architex.Repo, migration_timestamps: [type: :utc_datetime]

config :cors_plug,
  origin: ["*"],
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  headers: ["Origin", "X-Requested-With", "Content-Type", "Accept", "Authorization"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
