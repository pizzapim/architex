defmodule Architex.Event.Formatters do
  alias Architex.Event

  def for_client(%Event{
        content: content,
        type: type,
        id: event_id,
        sender: sender,
        origin_server_ts: origin_server_ts,
        unsigned: unsigned,
        room_id: room_id
      }) do
    data = %{
      content: content,
      type: type,
      event_id: event_id,
      sender: to_string(sender),
      origin_server_ts: origin_server_ts,
      room_id: room_id
    }

    data = if unsigned, do: Map.put(data, :unsigned, unsigned), else: data

    data
  end
end
