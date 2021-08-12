defmodule MatrixServer.SigningKey do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias MatrixServer.{Repo, SigningKey, ServerKeyInfo}

  @primary_key false
  schema "signing_keys" do
    field :signing_key_id, :string, primary_key: true
    field :signing_key, :binary

    belongs_to :server_key_info, ServerKeyInfo,
      foreign_key: :server_name,
      references: :server_name,
      type: :string,
      primary_key: true
  end

  def changeset(signing_key, params \\ %{}) do
    signing_key
    |> cast(params, [:server_name, :signing_key_id, :signing_key])
    |> validate_required([:server_name, :signing_key_id, :signing_key])
    |> unique_constraint([:server_name, :signing_key_id], name: :signing_keys_pkey)
  end

  def for_server(server_name) do
    SigningKey
    |> where([s], s.server_name == ^server_name)
    |> Repo.all()
  end
end
