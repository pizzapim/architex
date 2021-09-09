defmodule ArchitexWeb.Federation.Request.Profile do
  use ArchitexWeb.APIRequest

  alias Architex.Types.UserId

  @type t :: %__MODULE__{
          user_id: UserId.t(),
          field: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :user_id, UserId
    field :field, :string
  end

  def changeset(data, params) do
    data
    |> cast(params, [:user_id, :field])
    |> validate_required([:user_id])
    |> validate_inclusion(:field, ["displayname", "avatar_url"])
  end
end
