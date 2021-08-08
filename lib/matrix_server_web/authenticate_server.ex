defmodule MatrixServerWeb.AuthenticateServer do
  import Ecto.Changeset

  alias MatrixServer.SigningServer
  alias Ecto.Changeset

  @auth_header_regex ~r/^X-Matrix origin=(?<origin>.*),key="(?<key>.*)",sig="(?<sig>.*)"$/

  defmodule SignedJSON do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :method, :string
      field :uri, :string
      field :origin, :string
      field :destination, :string
      field :content, :map
      field :signatures, :map
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:method, :uri, :origin, :destination, :content, :signatures])
      |> validate_required([:method, :uri, :origin, :destination])
    end
  end

  def authenticated?(%Plug.Conn{body_params: params}) do
    with %Changeset{valid?: true} = cs <- SignedJSON.changeset(params),
         input <- apply_changes(cs) do
      verify_signature(input)
    else
      _ -> false
    end
  end

  defp verify_signature(%SignedJSON{signatures: signatures, origin: origin} = input) do
    if Map.has_key?(signatures, origin) do
      # TODO: fetch actual signing keys from cache/key store.
      signing_keys = SigningServer.get_signing_keys() |> Enum.into(%{})

      found_signatures =
        Enum.filter(signatures[origin], fn {key, _} ->
          case String.split(key, ":", parts: 2) do
            [algorithm, _] -> algorithm == "ed25519"
            _ -> false
          end
        end)
        |> Enum.map(fn {key_id, sig} ->
          if Map.has_key?(signing_keys, key_id) do
            {key_id, sig, signing_keys[key_id]}
          end
        end)
        |> Enum.reject(&Kernel.is_nil/1)

      with [{_, sig, signing_key} | _] <- found_signatures,
           {:ok, raw_sig} <- MatrixServer.decode_base64(sig),
           serializable_input <- MatrixServer.to_serializable_map(input),
           {:ok, encoded_input} <- MatrixServer.encode_canonical_json(serializable_input) do
        :enacl.sign_verify_detached(raw_sig, encoded_input, signing_key)
      else
        _ -> false
      end
    else
      false
    end
  end

  # TODO: Not actually needed?
  def parse_authorization_headers(headers) do
    headers
    |> Enum.filter(&(elem(&1, 0) == "authorization"))
    |> Enum.map(fn {_, auth_header} ->
      Regex.named_captures(@auth_header_regex, auth_header)
    end)
    |> Enum.reject(&Kernel.is_nil/1)
    |> Enum.reduce(%{}, fn %{"origin" => origin, "key" => key, "sig" => sig}, acc ->
      Map.update(acc, origin, %{key => sig}, &Map.put(&1, key, sig))
    end)
  end

  defmacro __using__(opts) do
    except = Keyword.get(opts, :except) || []

    quote do
      def action(conn, _) do
        action = action_name(conn)

        if action not in unquote(except) and
             not MatrixServerWeb.AuthenticateServer.authenticated?(conn) do
          IO.puts("Not authorized!")
          apply(__MODULE__, action, [conn, conn.params])
        else
          apply(__MODULE__, action, [conn, conn.params])
        end
      end
    end
  end
end
