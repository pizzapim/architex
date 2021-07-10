# https://gist.github.com/char0n/6fca76e886a2cfbd3aaa05526f287728
defmodule MatrixServerWeb.API.Login do
  use Ecto.Schema

  import Ecto.Changeset

  # TODO: Maybe use inline embedded schema here
  # https://hexdocs.pm/ecto/Ecto.Schema.html#embeds_one/3
  defmodule MatrixServerWeb.API.Login.Identifier do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :type, :string
      field :user, :string
    end

    def changeset(identifier, params) do
      identifier
      |> cast(params, [:type, :user])
      |> validate_required([:type, :user])
    end
  end

  alias MatrixServerWeb.API.Login.Identifier

  @primary_key false
  embedded_schema do
    field :type, :string
    field :password, :string
    field :device_id, :string
    field :initial_device_display_name, :string
    embeds_one :identifier, Identifier
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:type, :password, :device_id, :initial_device_display_name])
    |> cast_embed(:identifier, with: &Identifier.changeset/2, required: true)
    |> validate_required([:type, :password])
  end
end
