defmodule MatrixServerWeb.API.CreateRoom do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :visibility, :string
    field :room_alias_name, :string
    field :name, :string
    field :topic, :string
    field :invite, {:array, :string}
    field :room_version, :string
    # TODO: unimplemented:
    # creation_content, initial_state, invite_3pid, initial_state, preset,
    # is_direct, power_level_content_override
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:visibility, :room_alias_name, :name, :topic, :invite, :room_version])
  end

  def get_error(%Changeset{errors: [error | _]}), do: get_error(error)
  def get_error(_), do: :bad_json
end
