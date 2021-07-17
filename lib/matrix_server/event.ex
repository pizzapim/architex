defmodule MatrixServer.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias MatrixServer.{Room, Event, Account}
  alias MatrixServerWeb.API.CreateRoom

  @primary_key {:event_id, :string, []}
  schema "events" do
    field :type, :string
    field :origin_server_ts, :integer
    field :state_key, :string
    field :sender, :string
    field :content, :map
    field :prev_events, {:array, :string}
    field :auth_events, {:array, :string}
    belongs_to :room, Room, type: :string
  end

  def changeset(event, params \\ %{}) do
    # TODO: prev/auth events?
    event
    |> cast(params, [:type, :timestamp, :state_key, :sender, :content])
    |> validate_required([:type, :timestamp, :sender])
  end

  def new(room_id, sender) do
    %Event{
      room_id: room_id,
      sender: sender,
      event_id: generate_event_id(),
      origin_server_ts: DateTime.utc_now() |> DateTime.to_unix(),
      prev_events: [],
      auth_events: []
    }
  end

  def create_room(room_id, creator, room_version) do
    %Event{
      new(room_id, creator)
      | type: "m.room.create",
        state_key: "",
        content: %{
          creator: creator,
          room_version: room_version || MatrixServer.default_room_version()
        }
    }
  end

  def join(room_id, sender) do
    %Event{
      new(room_id, sender)
      | type: "m.room.member",
        state_key: sender,
        content: %{
          membership: "invite"
        }
    }
  end

  def room_creation_create_room(%CreateRoom{room_version: room_version}, %Account{
        localpart: localpart
      }) do
    fn repo, %{room: %Room{id: room_id}} ->
      # TODO: state resolution
      create_room(room_id, MatrixServer.get_mxid(localpart), room_version)
      |> repo.insert()
    end
  end

  def room_creation_join_creator do
    fn repo,
       %{
         create_room_event: %Event{sender: creator, event_id: create_room_event_id},
         room: %Room{id: room_id}
       } ->
      # TODO: state resolution
      join(room_id, creator)
      |> Map.put(:prev_events, [create_room_event_id])
      |> Map.put(:auth_events, [create_room_event_id])
      |> repo.insert()
    end
  end

  def room_creation_power_levels(_input) do
    fn _repo, %{} ->
      {:ok, :ok}
    end
  end

  def room_creation_name(_input) do
    fn _repo, %{} ->
      {:ok, :ok}
    end
  end

  def room_creation_topic(_input) do
    fn _repo, %{} ->
      {:ok, :ok}
    end
  end

  def generate_event_id do
    "$" <> MatrixServer.random_string(17) <> ":" <> MatrixServer.server_name()
  end
end
