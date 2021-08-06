use Mix.Config

hostname = "localhost"
port = System.get_env("PORT") || 4000

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :matrix_server, MatrixServer.Repo,
  username: "matrix_server",
  password: "matrix_server",
  database: "matrix_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: hostname,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :matrix_server, MatrixServerWeb.Endpoint,
  http: [port: port],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

config :matrix_server, server_name: "#{hostname}:#{port}"
config :matrix_server, private_key_file: "keys/id_ed25519"
