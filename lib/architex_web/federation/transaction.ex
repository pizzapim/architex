defmodule ArchitexWeb.Federation.Transaction do
  alias Architex.Event
  alias ArchitexWeb.Federation.Transaction

  # TODO
  @type edu :: any()

  @type t :: %__MODULE__{
          origin: String.t(),
          origin_server_ts: integer(),
          pdus: [Event.t()],
          edus: [edu()] | nil
        }

  defstruct [:origin, :origin_server_ts, :pdus, :edus]

  defimpl Jason.Encoder, for: Transaction do
    @fields [:origin, :origin_server_ts, :pdus, :edus]

    def encode(transaction, opts) do
      transaction
      |> Map.take(@fields)
      |> Jason.Encode.map(opts)
    end
  end

  @spec new([Event.t()], [edu()] | nil) :: t()
  def new(pdu_events, edus \\ nil) do
    %Transaction{
      origin: Architex.server_name(),
      origin_server_ts: System.os_time(:millisecond),
      pdus: Enum.map(pdu_events, &Architex.to_serializable_map/1),
      edus: edus
    }
  end
end
