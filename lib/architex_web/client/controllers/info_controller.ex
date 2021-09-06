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

  @doc """
  Gets information about the server's supported feature set and other relevant capabilities.

  Action for GET /_matrix/client/r0/capabilities.
  """
  def capabilities(conn, _params) do
    data = %{
      capabilities: %{
        "m.change_password": %{enabled: false},
        "m.room_versions": %{
          default: "5",
          available: %{"5": "stable"}
        }
      }
    }

    conn
    |> put_status(200)
    |> json(data)
  end
end
