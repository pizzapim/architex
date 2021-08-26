defmodule MatrixServer.Account do
  use Ecto.Schema

  import Ecto.{Changeset, Query}

  alias MatrixServer.{Repo, Account, Device, Room, JoinedRoom}
  alias MatrixServerWeb.Client.Request.{Register, Login}
  alias Ecto.{Multi, Changeset}

  @type t :: %__MODULE__{
          password_hash: String.t()
        }

  @max_mxid_length 255

  @primary_key {:localpart, :string, []}
  schema "accounts" do
    field :password_hash, :string, redact: true
    has_many :devices, Device, foreign_key: :localpart

    many_to_many :joined_rooms, Room,
      join_through: JoinedRoom,
      join_keys: [localpart: :localpart, room_id: :id]

    timestamps(updated_at: false)
  end

  @doc """
  Reports whether the given user localpart is available on this server.
  """
  @spec available?(String.t()) :: :ok | {:error, :user_in_use | :invalid_username}
  def available?(localpart) when is_binary(localpart) do
    if Regex.match?(MatrixServer.localpart_regex(), localpart) and
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

  @doc """
  Return an multi to register a new user.
  """
  @spec register(Register.t()) :: Multi.t()
  def register(%Register{} = input) do
    account_params = %{
      localpart: input.username || MatrixServer.random_string(10, ?a..?z),
      password_hash: Bcrypt.hash_pwd_salt(input.password)
    }

    Multi.new()
    |> Multi.insert(:account, changeset(%Account{}, account_params))
    |> Multi.insert(:device, fn %{account: account} ->
      device_params = %{
        display_name: input.initial_device_display_name,
        device_id: input.device_id || Device.generate_device_id(account.localpart)
      }

      Ecto.build_assoc(account, :devices)
      |> Device.changeset(device_params)
    end)
    |> Multi.run(:device_with_access_token, &Device.insert_new_access_token/2)
  end

  @doc """
  Return a function to log a user in.
  """
  @spec login(Login.t()) :: (Ecto.Repo.t() -> {:error, any()} | {:ok, Device.t()})
  def login(%Login{} = input) do
    localpart = try_get_localpart(input.identifier.user)

    fn repo ->
      case repo.one(from a in Account, where: a.localpart == ^localpart) do
        %Account{password_hash: hash} = account ->
          if Bcrypt.verify_pass(input.password, hash) do
            case Device.login(input, account) do
              {:ok, device} ->
                device

              {:error, _cs} ->
                repo.rollback(:forbidden)
            end
          else
            repo.rollback(:forbidden)
          end

        nil ->
          repo.rollback(:forbidden)
      end
    end
  end

  @doc """
  Get a device and its associated account using the device's access token.
  """
  @spec by_access_token(String.t()) :: {Account.t(), Device.t()} | nil
  def by_access_token(access_token) do
    Device
    |> where([d], d.access_token == ^access_token)
    |> join(:inner, [d], a in assoc(d, :account))
    |> select([d, a], {a, d})
    |> Repo.one()
  end

  @spec changeset(map(), map()) :: Changeset.t()
  def changeset(account, params \\ %{}) do
    # TODO: fix password_hash in params
    account
    |> cast(params, [:localpart, :password_hash])
    |> validate_required([:localpart, :password_hash])
    |> validate_length(:password_hash, max: 60)
    |> validate_format(:localpart, MatrixServer.localpart_regex())
    |> validate_length(:localpart, max: localpart_length())
    |> unique_constraint(:localpart, name: :accounts_pkey)
  end

  @spec localpart_length :: integer()
  defp localpart_length do
    # Subtract the "@" and ":" in the MXID.
    @max_mxid_length - 2 - String.length(MatrixServer.server_name())
  end

  @spec try_get_localpart(String.t()) :: String.t()
  defp try_get_localpart("@" <> rest = user_id) do
    case String.split(rest, ":", parts: 2) do
      [localpart, _] -> localpart
      _ -> user_id
    end
  end

  defp try_get_localpart(localpart), do: localpart

  @doc """
  Get the matrix user ID of an account.
  """
  @spec get_mxid(Account.t()) :: String.t()
  def get_mxid(%Account{localpart: localpart}) do
    "@" <> localpart <> ":" <> MatrixServer.server_name()
  end
end
