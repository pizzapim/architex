defmodule Architex.Event.Formatters do
  @moduledoc """
  Functions to format events in order to convert them to JSON.
  """
  alias Architex.Event

  @spec for_client(Event.t()) :: map()
  def for_client(%Event{
        content: content,
        type: type,
        id: event_id,
        sender: sender,
        origin_server_ts: origin_server_ts,
        unsigned: unsigned,
        room_id: room_id,
        state_key: state_key
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
    data = if state_key, do: Map.put(data, :state_key, state_key), else: data

    data
  end

  @spec as_pdu(Event.t()) :: map()
  def as_pdu(%Event{
        auth_events: auth_events,
        content: content,
        depth: depth,
        hashes: hashes,
        origin: origin,
        origin_server_ts: origin_server_ts,
        prev_events: prev_events,
        redacts: redacts,
        room_id: room_id,
        sender: sender,
        signatures: signatures,
        state_key: state_key,
        type: type,
        unsigned: unsigned
      }) do
    data = %{
      auth_events: auth_events,
      content: content,
      depth: depth,
      hashes: hashes,
      origin: origin,
      origin_server_ts: origin_server_ts,
      prev_events: prev_events,
      room_id: room_id,
      sender: to_string(sender),
      signatures: signatures,
      type: type
    }

    data = if redacts, do: Map.put(data, :redacts, redacts), else: data
    data = if state_key, do: Map.put(data, :state_key, state_key), else: data
    data = if unsigned, do: Map.put(data, :unsigned, unsigned), else: data

    data
  end
end
