defmodule MatrixServerWeb.Federation.Request.GetSigningKeys do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :server_name, :string
    field :verify_keys, {:map, {:map, :string}}
    field :old_verify_keys, {:map, :map}
    field :signatures, {:map, {:map, :string}}
    field :valid_until_ts, :integer
  end

  def changeset(params) do
    # TODO: There must be a better way to validate embedded maps?
    %__MODULE__{}
    |> cast(params, [:server_name, :verify_keys, :old_verify_keys, :signatures, :valid_until_ts])
    |> validate_required([:server_name, :verify_keys, :valid_until_ts])
    |> MatrixServer.validate_change_simple(:verify_keys, fn map ->
      Enum.all?(map, fn {_, map} ->
        is_map_key(map, "key")
      end)
    end)
    |> MatrixServer.validate_change_simple(:old_verify_keys, fn map ->
      Enum.all?(map, fn
        {_, %{"key" => key, "expired_ts" => expired_ts}}
        when is_binary(key) and is_integer(expired_ts) ->
          true

        _ ->
          false
      end)
    end)
  end
end
