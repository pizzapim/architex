defmodule MatrixServer.SigningServer do
  use GenServer

  alias MatrixServer.OrderedMap

  # TODO: only support one signing key for now.
  @signing_key_id "ed25519:1"

  ## Interface

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def sign_object(object) do
    GenServer.call(__MODULE__, {:sign_object, object})
  end

  def get_signing_keys do
    GenServer.call(__MODULE__, :get_signing_keys)
  end

  ## Implementation

  @impl true
  def init(_opts) do
    {public_key, private_key} = get_keys()
    {:ok, %{public_key: public_key, private_key: private_key}}
  end

  # https://blog.swwomm.com/2020/09/elixir-ed25519-signatures-with-enacl.html
  @impl true
  def handle_call(
        {:sign_object, object},
        _from,
        %{private_key: private_key} = state
      ) do
    ordered_map =
      object
      |> Map.drop([:signatures, :unsigned])
      |> OrderedMap.from_map()

    case Jason.encode(ordered_map) do
      {:ok, json} ->
        signature =
          json
          |> :enacl.sign_detached(private_key)
          |> MatrixServer.encode_unpadded_base64()

        signature_map = %{@signing_key_id => signature}
        servername = MatrixServer.server_name()

        signed_object =
          Map.update(object, :signatures, %{servername => signature_map}, fn signatures ->
            Map.put(signatures, servername, signature_map)
          end)

        {:reply, {:ok, signed_object}, state}

      {:error, _msg} ->
        {:reply, {:error, :json_encode}, state}
    end
  end

  def handle_call(:get_signing_keys, _from, %{public_key: public_key} = state) do
    encoded_public_key = MatrixServer.encode_unpadded_base64(public_key)

    {:reply, [{@signing_key_id, encoded_public_key}], state}
  end

  # TODO: not sure if there is a better way to do this...
  defp get_keys do
    raw_priv_key =
      Application.get_env(:matrix_server, :private_key_file)
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
