defmodule ArchitexWeb.Client.AliasesController do
  use ArchitexWeb, :controller

  import ArchitexWeb.Error

  alias Architex.Alias

  @doc """
  Create a new mapping from room alias to room ID.

  Action for PUT /_matrix/client/r0/directory/room/{roomAlias}.
  """
  def create(conn, %{"alias" => alias, "room_id" => room_id}) do
    case Alias.create(alias, room_id) do
      {:ok, _} ->
        conn
        |> put_status(200)
        |> json(%{})

      {:error, cs} ->
        put_error(conn, Alias.get_error(cs))
    end
  end

  # TODO: create error view for this?
  def create(conn, _), do: put_error(conn, :bad_json)
end
