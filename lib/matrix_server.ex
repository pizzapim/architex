defmodule MatrixServer do
  import Ecto.Changeset
  alias Ecto.Changeset

  def convert_change(changeset, old_name, new_name) do
    convert_change(changeset, old_name, new_name, &Function.identity/1)
  end

  def convert_change(changeset, old_name, new_name, f) do
    case changeset do
      %Changeset{valid?: true, changes: changes} ->
        case Map.fetch(changes, old_name) do
          {:ok, value} ->
            changeset
            |> put_change(new_name, f.(value))
            |> delete_change(old_name)

          :error ->
            changeset
        end

      _ ->
        changeset
    end
  end

  def validate_api_schema(params, {types, allowed, required}) do
    {%{}, types}
    |> cast(params, allowed)
    |> validate_required(required)
  end

  def get_mxid(localpart) when is_binary(localpart) do
    "@#{localpart}:#{server_name()}"
  end

  def server_name do
    Application.get_env(:matrix_server, :server_name)
  end

  def update_map_entry(map, old_key, new_key) do
    update_map_entry(map, old_key, new_key, &Function.identity/1)
  end

  def update_map_entry(map, old_key, new_key, fun) when is_map_key(map, old_key) do
    value = Map.fetch!(map, old_key)

    map
    |> Map.put(new_key, fun.(value))
    |> Map.delete(old_key)
  end

  def update_map_entry(map, _, _, _), do: map
end
