# https://gist.github.com/char0n/6fca76e886a2cfbd3aaa05526f287728
defmodule MatrixServerWeb.API.Login do
  use Ecto.Schema

  import Ecto.Changeset

  defmodule MatrixServerWeb.API.Login.Identifier do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :type, :string
      field :user, :string
    end

    def changeset(identifier, attrs) do
      identifier
      |> cast(attrs, [:type, :user])
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

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:type, :password, :device_id, :initial_device_display_name])
    |> cast_embed(:identifier, with: &Identifier.changeset/2, required: true)
    |> validate_required([:type, :password])
  end
end
