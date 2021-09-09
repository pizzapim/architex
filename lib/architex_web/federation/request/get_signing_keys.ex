defmodule ArchitexWeb.Federation.Request.GetSigningKeys do
  use ArchitexWeb.Request

  @type t :: %__MODULE__{
          server_name: String.t(),
          verify_keys: %{optional(String.t()) => %{String.t() => String.t()}},
          old_verify_keys: %{optional(String.t()) => map()},
          signatures: %{optional(String.t()) => %{optional(String.t()) => String.t()}},
          valid_until_ts: integer()
        }

  @primary_key false
  embedded_schema do
    field :server_name, :string
    field :verify_keys, {:map, {:map, :string}}
    field :old_verify_keys, {:map, :map}
    field :signatures, {:map, {:map, :string}}
    field :valid_until_ts, :integer
  end

  def changeset(data, params) do
    data
    |> cast(params, [:server_name, :verify_keys, :old_verify_keys, :signatures, :valid_until_ts])
    |> validate_required([:server_name, :verify_keys, :valid_until_ts])
    |> Architex.validate_change_truthy(:verify_keys, fn map ->
      Enum.all?(map, fn {_, map} ->
        is_map_key(map, "key")
      end)
    end)
    |> Architex.validate_change_truthy(:old_verify_keys, fn map ->
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
