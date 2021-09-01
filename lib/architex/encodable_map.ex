# https://github.com/michalmuskala/jason/issues/69
defmodule Architex.EncodableMap do
  alias Architex.EncodableMap
  alias Architex.Types.{UserId, RoomId, EventId, GroupId, AliasId}

  defstruct pairs: []

  defimpl Jason.Encoder, for: EncodableMap do
    def encode(%{pairs: pairs}, opts) do
      Jason.Encode.keyword(pairs, opts)
    end
  end

  def from_map(map) do
    pairs =
      map
      |> Enum.map(fn
        {k, v}
        when is_struct(v, UserId) or is_struct(v, RoomId) or is_struct(v, EventId) or
               is_struct(v, GroupId) or is_struct(v, AliasId) ->
          # Simply convert IDs to a string.
          {k, to_string(v)}

        {k, v} when is_map(v) ->
          {k, from_map(v)}

        x ->
          x
      end)
      |> Enum.sort()

    %EncodableMap{pairs: pairs}
  end
end
