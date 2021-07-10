defmodule MatrixServer.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias MatrixServer.Room

  schema "events" do
    field :type, :string
    field :timestamp, :naive_datetime
    field :state_key, :string
    field :sender, :string
    field :content, :string
    field :prev_events, {:array, :string}
    field :auth_events, {:array, :string}
    belongs_to :room, Room
  end

  def changeset(event, params \\ %{}) do
    # TODO: prev/auth events?
    event
    |> cast(params, [:type, :timestamp, :state_key, :sender, :content])
    |> validate_required([:type, :timestamp, :sender])
  end
end
