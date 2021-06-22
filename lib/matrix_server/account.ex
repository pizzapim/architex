defmodule MatrixServer.Account do
  use Ecto.Schema
  import Ecto.{Changeset, Query}
  alias MatrixServer.{Repo, Account}

  @max_mxid_length 255
  @localpart_regex ~r/^([a-z0-9\._=\/])+$/

  @primary_key {:localpart, :string, []}
  schema "accounts" do
    field :password_hash, :string, redact: true

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

  def changeset(%Account{} = account, attrs) do
    account
    |> cast(attrs, [:localpart, :password_hash])
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

  defp server_name do
    Application.get_env(:matrix_server, :server_name)
  end
end
