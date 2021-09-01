use Mix.Config

hostname = "localhost"
port = System.get_env("PORT") || 4000

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :architex, Architex.Repo,
  username: "architex",
  password: "architex",
  database: "architex_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: hostname,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :architex, ArchitexWeb.Endpoint,
  http: [port: port],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

config :architex, server_name: "#{hostname}:#{port}"
config :architex, private_key_file: "keys/id_ed25519"
