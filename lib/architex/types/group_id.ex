defmodule Architex.Types.GroupId do
  use Ecto.Type

  alias Architex.Types.GroupId

  defstruct [:localpart, :domain]

  @localpart_regex ~r/^[[:lower:][:digit:]._=\-\/]+$/

  defimpl String.Chars, for: GroupId do
    def to_string(%GroupId{localpart: localpart, domain: domain}) do
      "+" <> localpart <> ":" <> domain
    end
  end

  def type(), do: :string

  def cast(s) when is_binary(s) do
    with "+" <> rest <- s,
         [localpart, domain] <- String.split(rest, ":", parts: 2) do
      if String.length(localpart) + String.length(domain) + 2 <= 255 and
           Regex.match?(@localpart_regex, localpart) and
           Architex.valid_domain?(domain) do
        {:ok, %GroupId{localpart: localpart, domain: domain}}
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

    {:ok, %GroupId{localpart: localpart, domain: domain}}
  end

  def load(_), do: :error

  def dump(%GroupId{} = group_id), do: {:ok, to_string(group_id)}
  def dump(_), do: :error
end
