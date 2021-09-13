defmodule ArchitexWeb.Client.Request.CreateRoom do
  use ArchitexWeb.APIRequest

  alias Architex.Types.UserId

  defmodule PowerLevelContentOverride do
    use Ecto.Schema

    defmodule Notifications do
      use Ecto.Schema

      @type t :: %__MODULE__{
              room: integer() | nil
            }

      @primary_key false
      embedded_schema do
        field :room, :integer
      end

      def changeset(data, params) do
        cast(data, params, [:room])
      end
    end

    @type t :: %__MODULE__{
            ban: integer() | nil,
            events: %{optional(String.t()) => integer()} | nil,
            events_default: integer() | nil,
            invite: integer() | nil,
            kick: integer() | nil,
            redact: integer() | nil,
            state_default: integer() | nil,
            users: %{optional(String.t()) => integer()} | nil,
            users_default: integer() | nil,
            notifications: Notifications.t() | nil
          }

    @primary_key false
    embedded_schema do
      field :ban, :integer
      field :events, {:map, :integer}
      field :events_default, :integer
      field :invite, :integer
      field :kick, :integer
      field :redact, :integer
      field :state_default, :integer
      field :users, {:map, :integer}
      field :users_default, :integer

      embeds_one :notifications, Notifications
    end

    def changeset(data, params) do
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
        with: &Notifications.changeset/2,
        required: false
      )
    end
  end

  defmodule StateEvent do
    use Ecto.Schema

    @type t :: %__MODULE__{
            type: String.t(),
            state_key: String.t(),
            content: %{optional(String.t()) => any()}
          }

    @primary_key false
    embedded_schema do
      field :type, :string
      field :state_key, :string, default: ""
      field :content, :map
    end

    def changeset(data, params) do
      data
      |> cast(params, [:type, :state_key, :content])
      |> validate_required([:type, :content])
    end
  end

  @type t :: %__MODULE__{
          visibility: String.t() | nil,
          room_alias_name: String.t() | nil,
          name: String.t() | nil,
          topic: String.t() | nil,
          invite: [UserId.t()] | nil,
          room_version: String.t() | nil,
          preset: String.t() | nil,
          is_direct: boolean() | nil,
          creation_content: %{optional(String.t()) => any()} | nil,
          power_level_content_override: PowerLevelContentOverride.t() | nil,
          initial_state: [StateEvent.t()] | nil
        }

  @primary_key false
  embedded_schema do
    # TODO: unimplemented: invite_3pid and room_alias_name
    field :visibility, :string
    field :room_alias_name, :string
    field :name, :string
    field :topic, :string
    field :invite, {:array, UserId}
    field :room_version, :string
    field :preset, :string
    field :is_direct, :boolean
    field :creation_content, :map

    embeds_many :initial_state, StateEvent
    embeds_one :power_level_content_override, PowerLevelContentOverride
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
      :is_direct,
      :creation_content
    ])
    |> cast_embed(:power_level_content_override,
      with: &PowerLevelContentOverride.changeset/2,
      required: false
    )
    |> cast_embed(:initial_state, with: &StateEvent.changeset/2, required: false)
    |> validate_inclusion(:preset, ["private_chat", "public_chat", "trusted_private_chat"])
  end
end
