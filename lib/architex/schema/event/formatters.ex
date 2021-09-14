defmodule Architex.Event.Formatters do
  @moduledoc """
  Functions to format events in order to convert them to JSON.
  """
  alias Architex.Event

  @doc """
  Event format with keys that all formats have in common.
  """
  def base_client_response(%Event{
        content: content,
        type: type,
        id: event_id,
        sender: sender,
        origin_server_ts: origin_server_ts,
        unsigned: unsigned
      }) do
    data = %{
      content: content,
      type: type,
      event_id: event_id,
      sender: to_string(sender),
      origin_server_ts: origin_server_ts
    }

    if unsigned, do: Map.put(data, :unsigned, unsigned), else: data
  end

  @doc """
  The base event format, with room_id and state_key added.
  Used in the client /messages response.
  """
  @spec messages_response(Event.t()) :: map()
  def messages_response(%Event{room_id: room_id, state_key: state_key} = event) do
    data =
      base_client_response(event)
      |> Map.put(:room_id, room_id)

    if state_key, do: Map.put(data, :state_key, state_key), else: data
  end

  @doc """
  The event format used in the client /state response.
  TODO: prev_content
  """
  def state_response(event), do: messages_response(event)

  @doc """
  The base event format, used in the client /sync response.
  """
  @spec sync_response(Event.t()) :: map()
  def sync_response(event), do: base_client_response(event)

  @doc """
  The PDU format used for federation.
  """
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
