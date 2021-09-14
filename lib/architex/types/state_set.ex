defmodule Architex.Types.StateSet do
  use Ecto.Type

  import Ecto.Query

  alias Architex.{Repo, Event}

  @type t :: %{optional({String.t(), String.t()}) => Event.t()}

  def type(), do: {:array, :string}

  def cast(_), do: :error

  def load(event_ids) when is_list(event_ids) do
    events =
      Event
      |> where([e], e.id in ^event_ids)
      |> Repo.all()
      |> IO.inspect()

    if length(events) == length(event_ids) do
      state_set =
        Enum.into(events, %{}, fn %Event{type: type, state_key: state_key} = event ->
          {{type, state_key}, event}
        end)

      {:ok, state_set}
    else
      :error
    end
  end

  def load(_), do: :error

  def dump(state_set) when is_map(state_set) do
    dumped =
      Enum.map(state_set, fn {_, %Event{id: event_id}} ->
        event_id
      end)

    {:ok, dumped}
  end

  def dump(_), do: :error
end
