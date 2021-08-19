defmodule MatrixServer do
  alias MatrixServer.EncodableMap

  @random_string_alphabet Enum.into(?a..?z, []) ++ Enum.into(?A..?Z, [])
  @ipv6_regex ~r/^\[(?<ip>[^\]]+)\](?<port>:\d{1,5})?$/
  @ipv4_regex ~r/^(?<hostname>[^:]+)(?<port>:\d{1,5})?$/
  @dns_regex ~r/^[[:alnum:]-.]{1,255}$/

  @spec get_mxid(String.t()) :: String.t()
  def get_mxid(localpart) when is_binary(localpart) do
    "@#{localpart}:#{server_name()}"
  end

  @spec server_name() :: String.t()
  def server_name do
    Application.get_env(:matrix_server, :server_name)
  end

  @spec localpart_regex() :: Regex.t()
  def localpart_regex, do: ~r/^([a-z0-9\._=\/])+$/

  @spec random_string(pos_integer()) :: String.t()
  def random_string(length), do: random_string(length, @random_string_alphabet)

  @spec random_string(pos_integer(), Enum.t()) :: String.t()
  def random_string(length, alphabet) when length >= 1 do
    for _ <- 1..length, into: "", do: <<Enum.random(alphabet)>>
  end

  @spec default_room_version() :: String.t()
  def default_room_version, do: "7"

  @spec get_domain(String.t()) :: String.t() | nil
  def get_domain(id) do
    case String.split(id, ":", parts: 2) do
      [_, server_name] -> server_name
      _ -> nil
    end
  end

  # TODO Eventually move to regex with named captures.
  @spec get_localpart(String.t()) :: String.t() | nil
  def get_localpart(id) do
    with [part, _] <- String.split(id, ":", parts: 2),
         {_, localpart} <- String.split_at(part, 1) do
      localpart
    else
      _ -> nil
    end
  end

  # https://elixirforum.com/t/22709/9
  @spec has_duplicates?(list()) :: boolean()
  def has_duplicates?(list) do
    list
    |> Enum.reduce_while(%MapSet{}, fn x, acc ->
      if MapSet.member?(acc, x), do: {:halt, false}, else: {:cont, MapSet.put(acc, x)}
    end)
    |> is_boolean()
  end

  # https://matrix.org/docs/spec/appendices#unpadded-base64
  @spec encode_unpadded_base64(String.t()) :: String.t()
  def encode_unpadded_base64(data) do
    data
    |> Base.encode64()
    |> String.trim_trailing("=")
  end

  # Decode (possibly unpadded) base64.
  @spec decode_base64(String.t()) :: {:ok, String.t()} | :error
  def decode_base64(data) when is_binary(data) do
    rem = rem(String.length(data), 4)
    padded_data = if rem > 0, do: data <> String.duplicate("=", 4 - rem), else: data
    Base.decode64(padded_data)
  end

  @spec encode_canonical_json(map()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def encode_canonical_json(object) do
    object
    |> EncodableMap.from_map()
    |> Jason.encode()
  end

  # https://stackoverflow.com/questions/41523762/41671211
  @spec to_serializable_map(struct()) :: map()
  def to_serializable_map(struct) do
    association_fields = struct.__struct__.__schema__(:associations)
    waste_fields = association_fields ++ [:__meta__]

    struct
    |> Map.from_struct()
    |> Map.drop(waste_fields)
  end

  @spec serialize_and_encode(struct()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def serialize_and_encode(struct) do
    # TODO: handle nil values in struct?
    struct
    |> to_serializable_map()
    |> encode_canonical_json()
  end

  @spec add_signature(map(), String.t(), String.t()) :: map()
  def add_signature(object, key_id, sig) when not is_map_key(object, :signatures) do
    Map.put(object, :signatures, %{MatrixServer.server_name() => %{key_id => sig}})
  end

  def add_signature(%{signatures: sigs} = object, key_id, sig) do
    new_sigs =
      Map.update(sigs, MatrixServer.server_name(), %{key_id => sig}, &Map.put(&1, key_id, sig))

    %{object | signatures: new_sigs}
  end

  @spec validate_change_simple(Ecto.Changeset.t(), atom(), (term() -> boolean())) ::
          Ecto.Changeset.t()
  def validate_change_simple(changeset, field, func) do
    augmented_func = fn _, val ->
      if func.(val), do: [], else: [{field, "invalid"}]
    end

    Ecto.Changeset.validate_change(changeset, field, augmented_func)
  end

  # Returns a Boolean whether the signature is valid.
  # Also returns false on ArgumentError.
  @spec sign_verify(binary(), String.t(), binary()) :: boolean()
  def sign_verify(sig, text, key) do
    try do
      :enacl.sign_verify_detached(sig, text, key)
    rescue
      ArgumentError -> false
    end
  end

  @spec min_datetime(DateTime.t(), DateTime.t()) :: DateTime.t()
  def min_datetime(datetime1, datetime2) do
    if DateTime.compare(datetime1, datetime2) == :gt do
      datetime2
    else
      datetime1
    end
  end

  @spec encode_url_safe_base64(String.t()) :: String.t()
  def encode_url_safe_base64(data) do
    data
    |> encode_unpadded_base64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
  end

  @spec valid_domain?(String.t()) :: boolean()
  def valid_domain?(domain) do
    if String.starts_with?(domain, "[") do
      # Parse as ipv6.
      with %{"ip" => ip} <-
             Regex.named_captures(@ipv6_regex, domain),
           {:ok, _} <- :inet.parse_address(String.to_charlist(ip)) do
        true
      else
        _ -> false
      end
    else
      # Parse as ipv4 or dns name.
      case Regex.named_captures(@ipv4_regex, domain) do
        nil ->
          false

        %{"hostname" => hostname} ->
          # Try to parse as ipv4.
          case String.to_charlist(hostname) |> :inet.parse_address() do
            {:ok, _} ->
              true

            {:error, _} ->
              # Try to parse as dns name.
              Regex.match?(@dns_regex, hostname)
          end
      end
    end
  end
end
