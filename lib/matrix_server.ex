defmodule MatrixServer do
  @moduledoc """
  Utility functions used throughout the project.
  """

  alias MatrixServer.EncodableMap

  @random_string_alphabet Enum.into(?a..?z, []) ++ Enum.into(?A..?Z, [])
  @ipv6_regex ~r/^\[(?<ip>[^\]]+)\](?<port>:\d{1,5})?$/
  @ipv4_regex ~r/^(?<hostname>[^:]+)(?<port>:\d{1,5})?$/
  @dns_regex ~r/^[[:alnum:]-.]{1,255}$/

  @doc """
  Get the full MXID for a user's localpart, using the homeserver's
  server name as the domain.
  """
  @spec get_mxid(String.t()) :: String.t()
  def get_mxid(localpart) when is_binary(localpart) do
    "@#{localpart}:#{server_name()}"
  end

  @doc """
  Get the homeserver's server name.
  """
  @spec server_name() :: String.t()
  def server_name do
    Application.get_env(:matrix_server, :server_name)
  end

  @doc """
  Get a regex to match a user's localpart.
  """
  @spec localpart_regex() :: Regex.t()
  def localpart_regex, do: ~r/^([a-z0-9\._=\/])+$/

  @doc """
  Get a random string of `length` length and using `alphabet`'s characters.
  """
  @spec random_string(pos_integer(), Enum.t()) :: String.t()
  def random_string(length, alphabet \\ @random_string_alphabet) when length >= 1 do
    for _ <- 1..length, into: "", do: <<Enum.random(alphabet)>>
  end

  @doc """
  Get the homeserver's default room version.
  """
  @spec default_room_version() :: String.t()
  def default_room_version, do: "7"

  @doc """
  Get the domain from an ID.

  Return `nil` if no domain was found.
  No validation on the domain is performed whatsoever.
  """
  @spec get_domain(String.t()) :: String.t() | nil
  def get_domain(id) do
    case String.split(id, ":", parts: 2) do
      [_, server_name] -> server_name
      _ -> nil
    end
  end

  @doc """
  Get the localpart from a MXID.

  Return `nil` if no localpart was found.
  No validation on the localpart is performed whatsoever.
  """
  @spec get_localpart(String.t()) :: String.t() | nil
  def get_localpart(id) do
    with [part, _] <- String.split(id, ":", parts: 2),
         {_, localpart} <- String.split_at(part, 1) do
      localpart
    else
      _ -> nil
    end
  end

  @doc """
  Check whether the given list contains duplicates.
  """
  @spec has_duplicates?(list()) :: boolean()
  def has_duplicates?(list) do
    # https://elixirforum.com/t/22709/9
    list
    |> Enum.reduce_while(%MapSet{}, fn x, acc ->
      if MapSet.member?(acc, x), do: {:halt, false}, else: {:cont, MapSet.put(acc, x)}
    end)
    |> is_boolean()
  end

  @doc """
  Encode the given string using unpadded base64.

  Unpadded base64 is the same as base64, except the "=" padding is removed.
  """
  @spec encode_unpadded_base64(String.t()) :: String.t()
  def encode_unpadded_base64(data) do
    # https://matrix.org/docs/spec/appendices#unpadded-base64
    data
    |> Base.encode64()
    |> String.trim_trailing("=")
  end

  @doc """
  Decode the given base64 string.

  The base64 is allowed to be unpadded, as specified in `encode_unpadded_base64`.
  Return `:error` on decode error.
  """
  @spec decode_base64(String.t()) :: {:ok, String.t()} | :error
  def decode_base64(data) when is_binary(data) do
    rem = rem(String.length(data), 4)
    padded_data = if rem > 0, do: data <> String.duplicate("=", 4 - rem), else: data
    Base.decode64(padded_data)
  end

  @doc """
  Encode the given map as canonical JSON.

  See [the Matrix docs](https://matrix.org/docs/spec/appendices#canonical-json) for explanation
  for canonical JSON.
  Return an error if the map could not be encoded.
  """
  @spec encode_canonical_json(map()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def encode_canonical_json(object) do
    object
    |> EncodableMap.from_map()
    |> Jason.encode()
  end

  @doc """
  Convert a struct to a map, removing any schema or association fields,
  as well as fields that have `nil` values.
  """
  @spec to_serializable_map(struct()) :: map()
  def to_serializable_map(struct) do
    # https://stackoverflow.com/questions/41523762/41671211
    association_fields =
      if Kernel.function_exported?(struct.__struct__, :__schema__, 1) do
        struct.__struct__.__schema__(:associations)
      else
        []
      end

    waste_fields = association_fields ++ [:__meta__]

    struct
    |> Map.from_struct()
    |> Enum.reject(fn {k, v} ->
      is_nil(v) or k in waste_fields
    end)
    |> Enum.into(%{})
  end

  @doc """
  Serialize and encode the given struct.
  """
  @spec serialize_and_encode(struct()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def serialize_and_encode(struct) do
    struct
    |> to_serializable_map()
    |> encode_canonical_json()
  end

  @doc """
  Add a signature to the given map under the `:signatures` key.

  If the map has no `:signatures` key, it is created.
  """
  @spec add_signature(map(), String.t(), String.t()) :: map()
  def add_signature(object, key_id, sig) when not is_map_key(object, :signatures) do
    Map.put(object, :signatures, %{MatrixServer.server_name() => %{key_id => sig}})
  end

  def add_signature(%{signatures: sigs} = object, key_id, sig) do
    new_sigs =
      Map.update(sigs, MatrixServer.server_name(), %{key_id => sig}, &Map.put(&1, key_id, sig))

    %{object | signatures: new_sigs}
  end

  @doc """
  Validate a changeset's field where the reason for invalidation is not needed.
  """
  @spec validate_change_simple(Ecto.Changeset.t(), atom(), (term() -> boolean())) ::
          Ecto.Changeset.t()
  def validate_change_simple(changeset, field, func) do
    augmented_func = fn _, val ->
      if func.(val), do: [], else: [{field, "invalid"}]
    end

    Ecto.Changeset.validate_change(changeset, field, augmented_func)
  end

  @doc """
  Return a Boolean whether the given signature is valid.

  Returns `false` if `:enacl` throws an exception.
  """
  @spec sign_verify(binary(), String.t(), binary()) :: boolean()
  def sign_verify(sig, text, key) do
    try do
      :enacl.sign_verify_detached(sig, text, key)
    rescue
      ArgumentError -> false
    end
  end

  @doc """
  Get the earliest of the two given `DateTime`s.
  """
  @spec min_datetime(DateTime.t(), DateTime.t()) :: DateTime.t()
  def min_datetime(datetime1, datetime2) do
    if DateTime.compare(datetime1, datetime2) == :gt do
      datetime2
    else
      datetime1
    end
  end

  @doc """
  Encode the given string using URL-safe base64.

  URL-safe base64 is the same was unpadded base64, except "+" is replaced by "-"
  and "/" is replaced by "_".
  See [the Matrix docs](https://spec.matrix.org/unstable/rooms/v4/) for more details.
  """
  @spec encode_url_safe_base64(String.t()) :: String.t()
  def encode_url_safe_base64(data) do
    data
    |> encode_unpadded_base64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
  end

  @doc """
  Check whether the given domain (including port) is valid.

  The domain could be a DNS name, IPv4 or IPv6 address.
  See [the Matrix docs](https://matrix.org/docs/spec/appendices#server-name) for more details.
  """
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
