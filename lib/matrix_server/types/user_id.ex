defmodule MatrixServer.Types.UserId do
  use Ecto.Type

  alias MatrixServer.Types.UserId

  defstruct [:localpart, :domain]

  @localpart_regex ~r/^[a-z0-9._=\-\/]+$/

  defimpl String.Chars, for: UserId do
    def to_string(%UserId{localpart: localpart, domain: domain}) do
      "@" <> localpart <> ":" <> domain
    end
  end

  def type(), do: :string

  def cast(s) when is_binary(s) do
    with "@" <> rest <- s,
         [localpart, domain] <- String.split(rest, ":", parts: 2) do
      if String.length(localpart) + String.length(domain) + 2 <= 255 and
           Regex.match?(@localpart_regex, localpart) and MatrixServer.valid_domain?(domain) do
        %UserId{localpart: localpart, domain: domain}
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

    %UserId{localpart: localpart, domain: domain}
  end

  def load(_), do: :error

  def dump(%UserId{} = user_id), do: to_string(user_id)
  def dump(_), do: :error
end
