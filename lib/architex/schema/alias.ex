defmodule Architex.Alias do
  use Ecto.Schema

  import Ecto.Changeset

  alias Architex.{Repo, Alias, Room}
  alias Ecto.Changeset

  @type t :: %__MODULE__{
          alias: String.t(),
          room_id: String.t()
        }

  @primary_key {:alias, :string, []}
  schema "aliases" do
    belongs_to :room, Room, foreign_key: :room_id, references: :id, type: :string
  end

  def create(alias_, room_id) do
    change(%Alias{}, alias: alias_, room_id: room_id)
    |> assoc_constraint(:room)
    |> unique_constraint(:alias, name: :aliases_pkey)
    |> Repo.insert()
  end

  def get_error(%Changeset{errors: [error | _]}), do: get_error(error)
  def get_error({:alias, {_, [{:constraint, :unique} | _]}}), do: :room_alias_exists

  def get_error({:room, {_, [{:constraint, :assoc} | _]}}),
    do: {:not_found, "The room was not found."}

  def get_error(_), do: :bad_json
end
