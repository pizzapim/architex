defmodule Architex.Types.UserId do
  use Ecto.Type

  import Ecto.Query

  alias Architex.{Repo, Account}
  alias Architex.Types.UserId
  alias ArchitexWeb.Federation.HTTPClient

  @type t :: %__MODULE__{
          localpart: String.t(),
          domain: String.t()
        }

  defstruct [:localpart, :domain]

  @localpart_regex ~r/^[a-z0-9._=\-\/]+$/

  defimpl String.Chars, for: UserId do
    def to_string(%UserId{localpart: localpart, domain: domain}) do
      "@" <> localpart <> ":" <> domain
    end
  end

  defimpl Jason.Encoder, for: UserId do
    def encode(user_id, opts) do
      Jason.Encode.string(to_string(user_id), opts)
    end
  end

  def type(), do: :string

  def cast(s) when is_binary(s) do
    with "@" <> rest <- s,
         [localpart, domain] <- String.split(rest, ":", parts: 2) do
      if String.length(localpart) + String.length(domain) + 2 <= 255 and
           Regex.match?(@localpart_regex, localpart) and Architex.valid_domain?(domain) do
        {:ok, %UserId{localpart: localpart, domain: domain}}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  def cast(_), do: :error

  def load(s) when is_binary(s) do
    "@" <> rest = s
    [localpart, domain] = String.split(rest, ":", parts: 2)

    {:ok, %UserId{localpart: localpart, domain: domain}}
  end

  def load(_), do: :error

  def dump(%UserId{} = user_id), do: {:ok, to_string(user_id)}
  def dump(_), do: :error

  # TODO: Seems out of place here.
  @spec try_get_user_information(UserId.t()) :: {String.t() | nil, String.t() | nil}
  def try_get_user_information(%UserId{localpart: localpart, domain: domain} = user_id) do
    if domain == Architex.server_name() do
      # Get information about a user on this homeserver.
      query =
        Account
        |> where([a], a.localpart == ^localpart)
        |> select([a], {a.avatar_url, a.displayname})

      case Repo.one(query) do
        nil -> {nil, nil}
        info -> info
      end
    else
      # Get information about a user on another homeserver.
      client = HTTPClient.client(domain)

      case HTTPClient.query_profile(client, to_string(user_id)) do
        {:ok, response} ->
          avatar_url = Map.get(response, "avatar_url")
          avatar_url = if is_binary(avatar_url), do: avatar_url
          displayname = Map.get(response, "displayname")
          displayname = if is_binary(displayname), do: displayname

          {avatar_url, displayname}

        {:error, _, _} ->
          {nil, nil}
      end
    end
  end
end
