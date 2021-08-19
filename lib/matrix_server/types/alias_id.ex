defmodule MatrixServer.Types.AliasId do
  use Ecto.Type

  alias MatrixServer.Types.AliasId

  defstruct [:localpart, :domain]

  defimpl String.Chars, for: AliasId do
    def to_string(%AliasId{localpart: localpart, domain: domain}) do
      "#" <> localpart <> ":" <> domain
    end
  end

  def type(), do: :string

  def cast(s) when is_binary(s) do
    with "#" <> rest <- s,
         [localpart, domain] <- String.split(rest, ":", parts: 2) do
      if String.length(localpart) + String.length(domain) + 2 <= 255 and
           MatrixServer.valid_domain?(domain) do
        {:ok, %AliasId{localpart: localpart, domain: domain}}
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

    {:ok, %AliasId{localpart: localpart, domain: domain}}
  end

  def load(_), do: :error

  def dump(%AliasId{} = alias_id), do: {:ok, to_string(alias_id)}
  def dump(_), do: :error
end
