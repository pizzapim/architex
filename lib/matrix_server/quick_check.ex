defmodule MatrixServer.QuickCheck do
  import Ecto.Query

  alias MatrixServer.{Repo, Room, Account, RoomServer}
  alias MatrixServerWeb.API.CreateRoom

  def create_room(name \\ nil, topic \\ nil) do
    account = Repo.one!(from a in Account, limit: 1)
    input = %CreateRoom{name: name, topic: topic}
    %Room{id: room_id} = Repo.insert!(Room.create_changeset(input))
    {:ok, pid} = RoomServer.get_room_server(room_id)
    RoomServer.create_room(pid, account, input)
  end
end
