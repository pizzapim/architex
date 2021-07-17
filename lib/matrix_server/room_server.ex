defmodule MatrixServer.RoomServer do
  use GenServer

  alias MatrixServer.{Repo, Room, Event}
  alias MatrixServerWeb.API.CreateRoom
  alias Ecto.Multi

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def create_room(%CreateRoom{} = input, account) do
    GenServer.call(__MODULE__, {:create_room, input, account})
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_room, input, account}, _from, state) do
    # TODO: preset events, initial_state events, invite, invite_3pid
    result =
      Multi.new()
      |> Multi.insert(:room, Room.create_changeset(input))
      |> Multi.run(:create_room_event, Event.room_creation_create_room(input, account))
      |> Multi.run(:join_creator_event, Event.room_creation_join_creator())
      |> Multi.run(:power_levels_event, Event.room_creation_power_levels(input))
      |> Multi.run(:name_event, Event.room_creation_name(input))
      |> Multi.run(:topic_event, Event.room_creation_topic(input))
      |> Repo.transaction()

    {:reply, result, state}
  end
end
