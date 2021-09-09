defmodule ArchitexWeb.Federation.HTTPClient do
  @moduledoc """
  This module provides functions to interact with other homeservers
  using the Matrix federation API.
  """
  # TODO: Investigate request timeouts.
  use Tesla

  alias ArchitexWeb.Endpoint
  alias ArchitexWeb.Federation.Response.GetSigningKeys
  alias ArchitexWeb.Federation.Middleware.SignRequest
  alias ArchitexWeb.Router.Helpers, as: RouteHelpers

  @type t :: schema_response() | map_response()

  @type schema_response ::
          {:ok, struct()}
          | {:error, :status, Tesla.Env.t()}
          | {:error, :validation, Ecto.Changeset.t()}
          | {:error, :request, any()}

  @type map_response ::
          {:ok, map()}
          | {:error, :status, Tesla.Env.t()}
          | {:error, :validation, Ecto.Changeset.t()}
          | {:error, :request, any()}

  @adapter {Tesla.Adapter.Finch, name: ArchitexWeb.HTTPClient}

  @doc """
  Get a Tesla client for the given server name, to be used for
  interacting with other homeservers.
  """
  @spec client(String.t()) :: Tesla.Client.t()
  def client(server_name) do
    Tesla.client(
      [
        {Tesla.Middleware.Opts, [server_name: server_name]},
        SignRequest,
        {Tesla.Middleware.BaseUrl, "http://" <> server_name},
        Tesla.Middleware.JSON
      ],
      @adapter
    )
  end

  @doc """
  Get the signing keys of a homeserver.
  """
  @spec get_signing_keys(Tesla.Client.t()) :: {:ok, GetSigningKeys.t()} | :error
  def get_signing_keys(client) do
    path = RouteHelpers.key_path(Endpoint, :get_signing_keys)

    with {:ok,
          %GetSigningKeys{server_name: server_name, verify_keys: verify_keys, signatures: sigs} =
            response} <- tesla_request(:get, client, path, GetSigningKeys),
         serializable_response <- Architex.to_serializable_map(response),
         serializable_response <- Map.drop(serializable_response, [:signatures]),
         {:ok, encoded_body} <- Architex.encode_canonical_json(serializable_response),
         server_sigs when not is_nil(server_sigs) <- sigs[server_name] do
      # For each verify key, check if there is a matching signature.
      # If not, invalidate the whole response.
      Enum.all?(verify_keys, fn {key_id, %{"key" => key}} ->
        with true <- Map.has_key?(server_sigs, key_id),
             {:ok, decoded_key} <- Architex.decode_base64(key),
             {:ok, decoded_sig} <- Architex.decode_base64(server_sigs[key_id]) do
          Architex.sign_verify(decoded_sig, encoded_body, decoded_key)
        else
          _ -> false
        end
      end)
      |> then(fn
        true -> {:ok, response}
        false -> :error
      end)
    else
      _ -> :error
    end
  end

  @doc """
  Get the profile of a user.
  """
  @spec query_profile(Tesla.Client.t(), String.t(), String.t() | nil) :: map_response()
  def query_profile(client, user_id, field \\ nil) do
    path = RouteHelpers.query_path(Endpoint, :profile) |> Tesla.build_url(user_id: user_id)
    path = if field, do: Tesla.build_url(path, field: field), else: path

    tesla_request(:get, client, path)
  end

  # def get_event(client, event_id) do
  #   path = RouteHelpers.event_path(Endpoint, :event, event_id)

  #   Tesla.get(client, path)
  # end

  # def get_state(client, room_id, event_id) do
  #   path =
  #     RouteHelpers.event_path(Endpoint, :state, room_id) |> Tesla.build_url(event_id: event_id)

  #   Tesla.get(client, path)
  # end

  # def get_state_ids(client, room_id, event_id) do
  #   path =
  #     RouteHelpers.event_path(Endpoint, :state_ids, room_id)
  #     |> Tesla.build_url(event_id: event_id)

  #   Tesla.get(client, path)
  # end

  # Perform a Tesla request and validate the response with the given
  # Ecto schema struct.
  @spec tesla_request(atom(), Tesla.Client.t(), String.t(), module()) :: t()
  defp tesla_request(method, client, path, request_schema \\ nil) do
    case Tesla.request(client, url: path, method: method) do
      {:ok, %Tesla.Env{status: status} = env} when status != 200 ->
        {:error, :status, env}

      {:ok, %Tesla.Env{body: body}} ->
        if request_schema do
          case apply(request_schema, :parse, [body]) do
            {:ok, response} ->
              {:ok, response}

            {:error, changeset} ->
              {:error, :validation, changeset}
          end
        else
          {:ok, body}
        end

      {:error, tesla_error} ->
        {:error, :request, tesla_error}
    end
  end
end
