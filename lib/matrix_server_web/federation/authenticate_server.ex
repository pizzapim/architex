defmodule MatrixServerWeb.Federation.AuthenticateServer do
  import MatrixServerWeb.Error

  alias MatrixServer.{SigningKey, ServerKeyInfo}

  @auth_header_regex ~r/^X-Matrix origin=(?<origin>.*),key="(?<key>.*)",sig="(?<sig>.*)"$/

  def authenticate(%Plug.Conn{
        body_params: body_params,
        req_headers: headers,
        request_path: path,
        method: method,
        query_string: query_string
      }) do
    # TODO: This will break if request ends with '?'.
    uri = URI.decode_www_form(path)

    uri =
      if String.length(query_string) > 0 do
        uri <> "?" <> URI.decode_www_form(query_string)
      else
        uri
      end

    object_to_sign = %{
      uri: uri,
      method: method,
      destination: MatrixServer.server_name()
    }

    object_to_sign =
      if method != "GET", do: Map.put(object_to_sign, :content, body_params), else: object_to_sign

    object_fun = &Map.put(object_to_sign, :origin, &1)

    authenticate_with_headers(headers, object_fun)
  end

  defp authenticate_with_headers(headers, object_fun) do
    # TODO: Only query once per origin.
    headers
    |> parse_authorization_headers()
    |> Enum.find(:error, fn {origin, _, sig} ->
      object = object_fun.(origin)

      with {:ok, raw_sig} <- MatrixServer.decode_base64(sig),
           {:ok, encoded_object} <- MatrixServer.encode_canonical_json(object),
           {:ok, %ServerKeyInfo{signing_keys: keys}} <-
             ServerKeyInfo.with_fresh_signing_keys(origin) do
        Enum.find_value(keys, false, fn %SigningKey{signing_key: signing_key} ->
          with {:ok, decoded_key} <- MatrixServer.decode_base64(signing_key) do
            MatrixServer.sign_verify(raw_sig, encoded_object, decoded_key)
          else
            _ -> false
          end
        end)
      else
        _ -> false
      end
    end)
  end

  def parse_authorization_headers(headers) do
    headers
    |> Enum.filter(&(elem(&1, 0) == "authorization"))
    |> Enum.map(fn {_, auth_header} ->
      Regex.named_captures(@auth_header_regex, auth_header)
    end)
    |> Enum.reject(&Kernel.is_nil/1)
    |> Enum.map(fn %{"origin" => origin, "key" => key, "sig" => sig} ->
      {origin, key, sig}
    end)
    |> Enum.filter(fn {_, key, _} -> String.starts_with?(key, "ed25519:") end)
  end

  defmacro __using__(opts) do
    except = Keyword.get(opts, :except) || []

    quote do
      def action(conn, _) do
        action = action_name(conn)

        if action not in unquote(except) do
          case MatrixServerWeb.Federation.AuthenticateServer.authenticate(conn) do
            {origin, _key, _sig} ->
              conn = Plug.Conn.assign(conn, :origin, origin)
              apply(__MODULE__, action, [conn, conn.params])

            :error ->
              put_error(conn, :unauthorized, "Signature verification failed.")
          end
        else
          apply(__MODULE__, action, [conn, conn.params])
        end
      end
    end
  end
end
