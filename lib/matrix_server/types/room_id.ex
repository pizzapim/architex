defmodule MatrixServer.Types.RoomId do
  use Ecto.Type

  alias MatrixServer.Types.RoomId

  defstruct [:localpart, :domain]

  defimpl String.Chars, for: RoomId do
    def to_string(%RoomId{localpart: localpart, domain: domain}) do
      "!" <> localpart <> ":" <> domain
    end
  end

  def type(), do: :string

  def cast(s) when is_binary(s) do
    with "!" <> rest <- s,
         [localpart, domain] <- String.split(rest, ":", parts: 2) do
      if MatrixServer.valid_domain?(domain) do
        {:ok, %RoomId{localpart: localpart, domain: domain}}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  def cast(_), do: :error

  def load(s) when is_binary(s) do
    "!" <> rest = s
    [localpart, domain] = String.split(rest, ":", parts: 2)

    {:ok, %RoomId{localpart: localpart, domain: domain}}
  end

  def load(_), do: :error

  def dump(%RoomId{} = room_id), do: {:ok, to_string(room_id)}
  def dump(_), do: :error
end
