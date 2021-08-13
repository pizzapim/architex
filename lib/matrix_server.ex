defmodule MatrixServer do
  alias MatrixServer.OrderedMap

  def get_mxid(localpart) when is_binary(localpart) do
    "@#{localpart}:#{server_name()}"
  end

  def server_name do
    Application.get_env(:matrix_server, :server_name)
  end

  def maybe_update_map(map, old_key, new_key) do
    maybe_update_map(map, old_key, new_key, &Function.identity/1)
  end

  def maybe_update_map(map, old_key, new_key, fun) when is_map_key(map, old_key) do
    value = Map.fetch!(map, old_key)

    map
    |> Map.put(new_key, fun.(value))
    |> Map.delete(old_key)
  end

  def maybe_update_map(map, _, _, _), do: map

  def localpart_regex, do: ~r/^([a-z0-9\._=\/])+$/

  @alphabet Enum.into(?a..?z, []) ++ Enum.into(?A..?Z, [])
  def random_string(length), do: random_string(length, @alphabet)

  def random_string(length, alphabet) when length >= 1 do
    for _ <- 1..length, into: "", do: <<Enum.random(alphabet)>>
  end

  def default_room_version, do: "7"

  def get_domain(id) do
    case String.split(id, ":", parts: 2) do
      [_, server_name] -> server_name
      _ -> nil
    end
  end

  # TODO Eventually move to regex with named captures.
  def get_localpart(id) do
    with [part, _] <- String.split(id, ":", parts: 2),
         {_, localpart} <- String.split_at(part, 1) do
      localpart
    else
      _ -> nil
    end
  end

  # https://elixirforum.com/t/22709/9
  def has_duplicates?(list) do
    list
    |> Enum.reduce_while(%MapSet{}, fn x, acc ->
      if MapSet.member?(acc, x), do: {:halt, false}, else: {:cont, MapSet.put(acc, x)}
    end)
    |> is_boolean()
  end

  # https://matrix.org/docs/spec/appendices#unpadded-base64
  def encode_unpadded_base64(data) do
    data
    |> Base.encode64()
    |> String.trim_trailing("=")
  end

  # Decode (possibly unpadded) base64.
  def decode_base64(data) when is_binary(data) do
    rem = rem(String.length(data), 4)
    padded_data = if rem > 0, do: data <> String.duplicate("=", 4 - rem), else: data
    Base.decode64(padded_data)
  end

  def encode_canonical_json(object) do
    object
    |> Map.drop([:signatures, :unsigned])
    |> OrderedMap.from_map()
    |> Jason.encode()
  end

  # https://stackoverflow.com/questions/41523762/41671211
  def to_serializable_map(struct) do
    association_fields = struct.__struct__.__schema__(:associations)
    waste_fields = association_fields ++ [:__meta__]

    struct
    |> Map.from_struct()
    |> Map.drop(waste_fields)
  end

  def serialize_and_encode(struct) do
    # TODO: handle nil values in struct?
    struct
    |> to_serializable_map()
    |> encode_canonical_json()
  end

  def add_signature(object, key_id, sig) when not is_map_key(object, :signatures) do
    Map.put(object, :signatures, %{MatrixServer.server_name() => %{key_id => sig}})
  end

  def add_signature(%{signatures: sigs} = object, key_id, sig) do
    new_sigs =
      Map.update(sigs, MatrixServer.server_name(), %{key_id => sig}, &Map.put(&1, key_id, sig))

    %{object | signatures: new_sigs}
  end

  def validate_change_simple(changeset, field, func) do
    augmented_func = fn _, val ->
      if func.(val), do: [], else: [{field, "invalid"}]
    end

    Ecto.Changeset.validate_change(changeset, field, augmented_func)
  end
end
