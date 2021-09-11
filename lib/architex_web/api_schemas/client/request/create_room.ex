defmodule ArchitexWeb.Client.Request.CreateRoom do
  use ArchitexWeb.APIRequest

  @type t :: %__MODULE__{
          visibility: String.t() | nil,
          room_alias_name: String.t() | nil,
          name: String.t() | nil,
          topic: String.t() | nil,
          invite: list(String.t()) | nil,
          room_version: String.t() | nil,
          preset: String.t() | nil,
          is_direct: boolean() | nil,
          power_level_content_override: plco_t() | nil
        }

  @type plco_t :: %__MODULE__.PowerLevelContentOverride{
          ban: integer() | nil,
          events: %{optional(String.t()) => integer()} | nil,
          events_default: integer() | nil,
          invite: integer() | nil,
          kick: integer() | nil,
          redact: integer() | nil,
          state_default: integer() | nil,
          users: %{optional(String.t()) => integer()} | nil,
          users_default: integer() | nil,
          notifications: plco_n_t() | nil
        }

  @type plco_n_t :: %__MODULE__.PowerLevelContentOverride.Notifications{
          room: integer() | nil
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
    field :is_direct, :boolean

    embeds_one :power_level_content_override, PowerLevelContentOverride, primary_key: false do
      field :ban, :integer
      field :events, {:map, :integer}
      field :events_default, :integer
      field :invite, :integer
      field :kick, :integer
      field :redact, :integer
      field :state_default, :integer
      field :users, {:map, :integer}
      field :users_default, :integer

      embeds_one :notifications, Notifications, primary_key: false do
        field :room, :integer
      end
    end

    # TODO: unimplemented:
    # creation_content, initial_state, invite_3pid, initial_state
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
      :preset,
      :is_direct
    ])
    |> cast_embed(:power_level_content_override,
      with: &power_level_content_override_changeset/2,
      required: false
    )
    |> validate_inclusion(:preset, ["private_chat", "public_chat", "trusted_private_chat"])
  end

  def power_level_content_override_changeset(data, params) do
    data
    |> cast(params, [
      :ban,
      :events,
      :events_default,
      :invite,
      :kick,
      :redact,
      :state_default,
      :users,
      :users_default
    ])
    |> cast_embed(:notifications,
      with: &power_level_content_override_notifications_changeset/2,
      required: false
    )
  end

  def power_level_content_override_notifications_changeset(data, params) do
    cast(data, params, [:room])
  end
end
