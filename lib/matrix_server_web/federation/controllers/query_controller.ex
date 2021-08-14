defmodule MatrixServerWeb.Federation.QueryController do
  use MatrixServerWeb, :controller
  use MatrixServerWeb.Federation.AuthenticateServer

  import MatrixServerWeb.Error
  import Ecto.Query

  alias MatrixServer.{Repo, Account}

  defmodule ProfileRequest do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :user_id, :string
      field :field, :string
    end

    def validate(params) do
      %__MODULE__{}
      |> cast(params, [:user_id, :field])
      |> validate_required([:user_id])
      |> validate_inclusion(:field, ["displayname", "avatar_url"])
      |> then(fn
        %Ecto.Changeset{valid?: true} = cs -> {:ok, apply_changes(cs)}
        _ -> :error
      end)
    end
  end

  def profile(conn, params) do
    with {:ok, %ProfileRequest{user_id: user_id}} <- ProfileRequest.validate(params) do
      if MatrixServer.get_domain(user_id) == MatrixServer.server_name() do
        localpart = MatrixServer.get_localpart(user_id)

        case Repo.one(from a in Account, where: a.localpart == ^localpart) do
          %Account{} ->
            # TODO: Return displayname and avatar_url when we implement them.
            conn
            |> put_status(200)
            |> json(%{})

          nil ->
            put_error(conn, :not_found, "User does not exist.")
        end
      else
        put_error(conn, :not_found, "Wrong server name.")
      end
    else
      _ -> put_error(conn, :bad_json)
    end
  end
end
