defmodule Architex.Membership do
  use Ecto.Schema

  alias Architex.{Account, Room}

  @type t :: %__MODULE__{
          account_id: integer(),
          room_id: String.t(),
          membership: String.t()
        }

  @primary_key false
  schema "membership" do
    belongs_to :account, Account, primary_key: true
    belongs_to :room, Room, primary_key: true, type: :string
    field :membership, :string
  end
end
