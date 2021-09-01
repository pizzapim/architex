defmodule Architex.KeyServer do
  @moduledoc """
  A GenServer holding the homeserver's keys, and responsible for signing objects.

  Currently, it only supports one key pair that cannot expire.
  """

  use GenServer

  # TODO: only support one signing key for now.
  @signing_key_id "ed25519:1"

  ## Interface

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sign the given object using the homeserver's signing keys.

  Return the signature and the key ID used.
  On error, return `:error`.
  """
  @spec sign_object(map()) :: {:ok, String.t(), String.t()} | :error
  def sign_object(object) do
    GenServer.call(__MODULE__, {:sign_object, object})
  end

  @doc """
  Get the homeserver's signing keys.

  Return a list of tuples, each holding the key ID and the key itself.
  """
  @spec get_own_signing_keys() :: list({String.t(), binary()})
  def get_own_signing_keys() do
    GenServer.call(__MODULE__, :get_own_signing_keys)
  end

  ## Implementation

  @impl true
  def init(_opts) do
    {public_key, private_key} = read_keys()
    {:ok, %{public_key: public_key, private_key: private_key}}
  end

  @impl true
  def handle_call({:sign_object, object}, _from, %{private_key: private_key} = state) do
    case sign_object(object, private_key) do
      {:ok, signature} -> {:reply, {:ok, signature, @signing_key_id}, state}
      {:error, _reason} -> {:reply, :error, state}
    end
  end

  def handle_call(:get_own_signing_keys, _from, %{public_key: public_key} = state) do
    encoded_key = Architex.encode_unpadded_base64(public_key)

    {:reply, [{@signing_key_id, encoded_key}], state}
  end

  # https://blog.swwomm.com/2020/09/elixir-ed25519-signatures-with-enacl.html
  @spec sign_object(map(), binary()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  defp sign_object(object, private_key) do
    object = Map.drop(object, [:signatures, :unsigned])

    with {:ok, json} <- Architex.encode_canonical_json(object) do
      signature =
        json
        |> :enacl.sign_detached(private_key)
        |> Architex.encode_unpadded_base64()

      {:ok, signature}
    end
  end

  # TODO: not sure if there is a better way to do this...
  @spec read_keys() :: {binary(), binary()}
  defp read_keys do
    raw_priv_key =
      Application.get_env(:architex, :private_key_file)
      |> File.read!()

    "-----BEGIN OPENSSH PRIVATE KEY-----\n" <> rest = raw_priv_key

    %{public: public, secret: private} =
      String.split(rest, "\n")
      |> Enum.take_while(&(&1 != "-----END OPENSSH PRIVATE KEY-----"))
      |> Enum.join()
      |> Base.decode64!()
      |> :enacl.sign_seed_keypair()

    {public, private}
  end
end
