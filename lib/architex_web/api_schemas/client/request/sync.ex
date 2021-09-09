defmodule ArchitexWeb.Client.Request.Sync do
  use ArchitexWeb.APIRequest

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :filter, :string
    field :since, :string
    field :full_state, :boolean, default: false
    field :set_presence, :string, default: "online"
    field :timeout, :integer, default: 0
  end
end
