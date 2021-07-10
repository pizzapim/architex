defmodule MatrixServer.RoomServer do
  use GenServer

  alias MatrixServer.{Repo, Room}
  alias MatrixServerWeb.API.CreateRoom

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def create_room(params) do
    GenServer.call(__MODULE__, {:create_room, params})
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_room, %CreateRoom{} = api}, _from, state) do
    Room.create(api)
    |> Repo.transaction()

    {:reply, :ok, state}
  end
end
