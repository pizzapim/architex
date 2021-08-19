defmodule MatrixServer.Check do
  import Ecto.Query
  alias MatrixServer.{Repo, Account, Room}
  alias MatrixServerWeb.Client.Request.CreateRoom

  def create_room do
    account = Repo.one!(from a in Account, limit: 1)
    Room.create(account, %CreateRoom{})
  end
end
