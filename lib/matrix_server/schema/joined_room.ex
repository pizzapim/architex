defmodule MatrixServer.JoinedRoom do
  use Ecto.Schema

  alias MatrixServer.{Account, Room}

  @type t :: %__MODULE__{
          account_id: integer(),
          room_id: String.t()
        }

  @primary_key false
  schema "joined_rooms" do
    belongs_to :account, Account, primary_key: true

    belongs_to :room, Room, primary_key: true, type: :string
  end
end
