# https://github.com/michalmuskala/jason/issues/69
defmodule MatrixServer.OrderedMap do
  alias MatrixServer.OrderedMap

  defstruct pairs: []

  defimpl Jason.Encoder, for: OrderedMap do
    def encode(%{pairs: pairs}, opts) do
      Jason.Encode.keyword(pairs, opts)
    end
  end

  def from_map(map) do
    pairs =
      map
      |> Enum.map(fn
        {k, v} when is_map(v) ->
          {k, from_map(v)}

        x ->
          x
      end)
      |> Enum.sort()

    %OrderedMap{pairs: pairs}
  end
end
