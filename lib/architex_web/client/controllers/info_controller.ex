defmodule ArchitexWeb.Client.InfoController do
  use ArchitexWeb, :controller

  import ArchitexWeb.Error

  @supported_versions ["r0.6.1"]

  @doc """
  Gets the versions of the specification supported by the server.

  Action for GET /_matrix/client/versions.
  """
  def versions(conn, _params) do
    data = %{versions: @supported_versions}

    conn
    |> put_status(200)
    |> json(data)
  end

  def unrecognized(conn, _params) do
    put_error(conn, :unrecognized)
  end
end
