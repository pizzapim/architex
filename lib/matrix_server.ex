defmodule MatrixServer do
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
end
