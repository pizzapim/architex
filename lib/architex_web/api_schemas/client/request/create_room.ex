defmodule ArchitexWeb.Client.Request.CreateRoom do
  use ArchitexWeb.APIRequest

  @type t :: %__MODULE__{
          visibility: String.t() | nil,
          room_alias_name: String.t() | nil,
          name: String.t() | nil,
          topic: String.t() | nil,
          invite: list(String.t()) | nil,
          room_version: String.t() | nil,
          preset: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :visibility, :string
    field :room_alias_name, :string
    field :name, :string
    field :topic, :string
    field :invite, {:array, :string}
    field :room_version, :string
    field :preset, :string
    # TODO: unimplemented:
    # creation_content, initial_state, invite_3pid, initial_state,
    # is_direct, power_level_content_override
  end

  def changeset(data, params) do
    data
    |> cast(params, [
      :visibility,
      :room_alias_name,
      :name,
      :topic,
      :invite,
      :room_version,
      :preset
    ])
    |> validate_inclusion(:preset, ["private_chat", "public_chat", "trusted_private_chat"])
  end
end
