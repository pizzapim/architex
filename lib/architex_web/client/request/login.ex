defmodule ArchitexWeb.Client.Request.Login do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          type: String.t(),
          password: String.t(),
          device_id: String.t(),
          initial_device_display_name: String.t()
        }

  @primary_key false
  embedded_schema do
    field :type, :string
    field :password, :string
    field :device_id, :string
    field :initial_device_display_name, :string

    embeds_one :identifier, Identifier, primary_key: false do
      field :type, :string
      field :user, :string
    end
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:type, :password, :device_id, :initial_device_display_name])
    |> cast_embed(:identifier, with: &identifier_changeset/2, required: true)
    |> validate_required([:type, :password])
  end

  def identifier_changeset(identifier, params) do
    identifier
    |> cast(params, [:type, :user])
    |> validate_required([:type, :user])
  end
end
