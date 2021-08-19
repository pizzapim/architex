defmodule MatrixServer.Types.EventId do
  use Ecto.Type

  alias MatrixServer.Types.EventId

  defstruct [:id]

  @id_regex ~r/^[[:alnum:]-_]+$/

  defimpl String.Chars, for: EventId do
    def to_string(%EventId{id: id}) do
      "$" <> id
    end
  end

  def type(), do: :string

  def cast(s) when is_binary(s) do
    with "$" <> id <- s do
      if Regex.match?(@id_regex, id) do
        %EventId{id: id}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  def cast(_), do: :error

  def load(s) when is_binary(s) do
    "$" <> rest = s

    %EventId{id: rest}
  end

  def load(_), do: :error

  def dump(%EventId{} = event_id), do: to_string(event_id)
  def dump(_), do: :error
end
