defmodule MatrixServer.ServerKeyInfo do
  use Ecto.Schema

  import Ecto.Query

  alias MatrixServer.{Repo, ServerKeyInfo, SigningKey}
  alias MatrixServerWeb.FederationClient
  alias MatrixServerWeb.Federation.Request.GetSigningKeys
  alias Ecto.Multi

  @primary_key {:server_name, :string, []}
  schema "server_key_info" do
    field :valid_until, :integer

    has_many :signing_keys, SigningKey, foreign_key: :server_name
  end

  def with_fresh_signing_keys(server_name) do
    current_time = System.os_time(:millisecond)

    case with_signing_keys(server_name) do
      nil ->
        # We have not encountered this server before, always request keys.
        refresh_signing_keys(server_name)

      %ServerKeyInfo{valid_until: valid_until} when valid_until <= current_time ->
        # Keys are expired; request fresh ones from server.
        refresh_signing_keys(server_name)

      ski ->
        {:ok, ski}
    end
  end

  defp refresh_signing_keys(server_name) do
    # TODO: Handle expired keys.
    in_a_week = System.os_time(:millisecond) + 1000 * 60 * 60 * 24 * 7
    client = FederationClient.client(server_name)

    with {:ok,
          %GetSigningKeys{
            server_name: server_name,
            verify_keys: verify_keys,
            valid_until_ts: valid_until
          }} <-
           FederationClient.get_signing_keys(client) do
      signing_keys =
        Enum.map(verify_keys, fn {key_id, %{"key" => key}} ->
          [server_name: server_name, signing_key_id: key_id, signing_key: key]
        end)

      # Always check every week to prevent misuse.
      ski = %ServerKeyInfo{server_name: server_name, valid_until: min(valid_until, in_a_week)}

      case upsert_multi(server_name, ski, signing_keys) |> Repo.transaction() do
        {:ok, %{new_ski: ski}} -> {:ok, ski}
        {:error, _} -> :error
      end
    else
      :error ->
        :error
    end
  end

  defp upsert_multi(server_name, ski, signing_keys) do
    Multi.new()
    |> Multi.insert(:ski, ski,
      on_conflict: {:replace, [:valid_until]},
      conflict_target: [:server_name]
    )
    |> Multi.insert_all(:insert_keys, SigningKey, signing_keys, on_conflict: :nothing)
    |> Multi.run(:new_ski, fn _, _ ->
      case with_signing_keys(server_name) do
        nil -> {:error, :ski}
        ski -> {:ok, ski}
      end
    end)
  end

  defp with_signing_keys(server_name) do
    ServerKeyInfo
    |> where([ski], ski.server_name == ^server_name)
    |> preload([ski], [:signing_keys])
    |> Repo.one()
  end
end
