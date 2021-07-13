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
end
