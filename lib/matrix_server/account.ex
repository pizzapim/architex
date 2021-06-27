defmodule MatrixServer.Account do
  use Ecto.Schema

  import MatrixServer
  import Ecto.{Changeset, Query}

  alias MatrixServer.{Repo, Account, Device}
  alias Ecto.Multi

  @max_mxid_length 255
  @localpart_regex ~r/^([a-z0-9\._=\/])+$/

  @primary_key {:localpart, :string, []}
  schema "accounts" do
    field :password_hash, :string, redact: true
    has_many :devices, Device, foreign_key: :localpart
    timestamps(updated_at: false)
  end

  def available?(localpart) when is_binary(localpart) do
    if Regex.match?(@localpart_regex, localpart) and
         String.length(localpart) <= localpart_length() do
      if Repo.one!(
           Account
           |> where([a], a.localpart == ^localpart)
           |> select([a], count(a))
         ) == 0 do
        :ok
      else
        {:error, :user_in_use}
      end
    else
      {:error, :invalid_username}
    end
  end

  def register(params) do
    Multi.new()
    |> Multi.insert(:account, changeset(%Account{}, params))
    |> Multi.insert(:device, fn %{account: account} ->
      device_id = Device.generate_device_id(account.localpart)

      Ecto.build_assoc(account, :devices)
      |> Map.put(:device_id, device_id)
      |> Device.changeset(params)
    end)
    |> Multi.run(:device_with_access_token, &Device.insert_new_access_token/2)
  end

  def get_by_access_token(access_token) do
    from(a in Account,
      join: d in assoc(a, :devices),
      where: d.access_token == ^access_token,
      preload: [devices: d]
    )
    |> Repo.one()
  end

  def changeset(account, params \\ %{}) do
    account
    |> cast(params, [:localpart, :password_hash])
    |> validate_required([:localpart, :password_hash])
    |> validate_length(:password_hash, max: 60)
    |> validate_format(:localpart, @localpart_regex)
    |> validate_length(:localpart, max: localpart_length())
    |> unique_constraint(:localpart, name: :accounts_pkey)
  end

  defp localpart_length do
    # Subtract the "@" and ":" in the MXID.
    @max_mxid_length - 2 - String.length(server_name())
  end
end
