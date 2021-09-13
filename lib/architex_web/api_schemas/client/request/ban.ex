defmodule ArchitexWeb.Client.Request.Ban do
  use ArchitexWeb.APIRequest

  alias Architex.Types.UserId

  @type t :: %__MODULE__{
          user_id: UserId.t(),
          reason: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :user_id, UserId
    field :reason, :string
  end

  def changeset(data, params) do
    data
    |> cast(params, [:user_id, :reason])
    |> validate_required([:user_id])
  end
end
