defmodule Architex.Check do
  import Ecto.Query
  alias Architex.{Repo, Account, Room}
  alias ArchitexWeb.Client.Request.CreateRoom

  def create_room do
    account = Repo.one!(from a in Account, limit: 1)
    Room.create(account, %CreateRoom{})
  end
end
