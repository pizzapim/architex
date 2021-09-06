defmodule ArchitexWeb.Client.Request.Messages do
  use ArchitexWeb.Request

  @type t :: %__MODULE__{
    from: String.t(),
    to: String.t() | nil,
    dir: String.t(),
    limit: integer() | nil,
    filter: String.t() | nil
  }

  @primary_key false
  embedded_schema do
    field :from, :string
    field :to, :string
    field :dir, :string
    field :limit, :integer
    field :filter, :string
  end

  def changeset(data, params) do
    data
    |> cast(params, [:from, :to, :dir, :limit, :filter], empty_values: [])
    |> validate_required([:dir])
    |> Architex.validate_not_nil([:from])
    |> validate_inclusion(:dir, ["b", "f"])
    |> validate_number(:limit, greater_than: 0)
    |> validate_format(:from, ~r/^[0-9]*$/)
    |> validate_format(:to, ~r/^[0-9]+$/)
  end
end
