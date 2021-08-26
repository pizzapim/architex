defmodule MatrixServerWeb.Request do
  import Ecto.Changeset

  alias Ecto.Changeset

  @spec parse(module(), map()) :: {:ok, struct()} | {:error, Changeset.t()}
  def parse(module, params) do
    case apply(module, :changeset, [struct(module), params]) do
      %Ecto.Changeset{valid?: true} = cs -> {:ok, apply_changes(cs)}
      cs -> {:error, cs}
    end
  end

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      @spec parse(map()) :: {:ok, struct()} | {:error, Changeset.t()}
      def parse(params) do
        MatrixServerWeb.Request.parse(__MODULE__, params)
      end
    end
  end
end
