defmodule MatrixServer.JoinedRoom do
  use Ecto.Schema

  alias MatrixServer.{Account, Room}

  @type t :: %__MODULE__{
          localpart: String.t(),
          room_id: String.t()
        }

  @primary_key false
  schema "joined_rooms" do
    belongs_to :account, Account,
      foreign_key: :localpart,
      references: :localpart,
      type: :string,
      primary_key: true

    belongs_to :room, Room, primary_key: true, type: :string
  end
end
