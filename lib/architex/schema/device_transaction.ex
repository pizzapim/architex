defmodule Architex.DeviceTransaction do
  use Ecto.Schema

  alias Architex.Device

  @type t :: %__MODULE__{
          txn_id: String.t(),
          event_id: String.t(),
          device_id: integer()
        }

  @primary_key {:txn_id, :string, []}
  schema "device_transactions" do
    field :event_id, :string

    belongs_to :device, Device
  end
end
