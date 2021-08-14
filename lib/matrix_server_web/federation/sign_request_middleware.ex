defmodule MatrixServerWeb.Federation.Middleware.SignRequest do
  @behaviour Tesla.Middleware

  def call(%Tesla.Env{opts: opts} = env, next, _opts) do
    sign = Keyword.get(opts, :sign, true)

    case sign_request(env, sign) do
      %Tesla.Env{} = env -> Tesla.run(env, next)
      :error -> {:error, :sign_request}
    end
  end

  defp sign_request(env, false), do: env

  defp sign_request(%Tesla.Env{method: method, url: path, opts: opts} = env, true) do
    origin = MatrixServer.server_name()

    object_to_sign = %{
      method: Atom.to_string(method) |> String.upcase(),
      origin: origin,
      uri: URI.decode_www_form(path),
      destination: Keyword.fetch!(opts, :server_name)
    }

    with {:ok, sig, key_id} <- MatrixServer.KeyServer.sign_object(object_to_sign) do
      sigs = %{origin => %{key_id => sig}}
      auth_headers = create_signature_authorization_headers(sigs, origin)

      Tesla.put_headers(env, auth_headers)
    end
  end

  defp create_signature_authorization_headers(signatures, origin) do
    Enum.map(signatures[origin], fn {key, sig} ->
      {"Authorization", "X-Matrix origin=#{origin},key=\"#{key}\",sig=\"#{sig}\""}
    end)
  end
end
