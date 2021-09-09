defmodule ArchitexWeb.Federation.QueryController do
  use ArchitexWeb, :controller
  use ArchitexWeb.Federation.AuthenticateServer

  import ArchitexWeb.Error
  import Ecto.Query

  alias Architex.{Repo, Account}
  alias Architex.Types.UserId

  defmodule ProfileRequest do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :user_id, UserId
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

  @doc """
  Performs a query to get profile information, such as a display name or avatar,
  for a given user.

  Action for GET /_matrix/federation/v1/query/profile.
  """
  def profile(conn, params) do
    with {:ok,
          %ProfileRequest{user_id: %UserId{localpart: localpart, domain: domain}, field: field}} <-
           ProfileRequest.validate(params) do
      if domain == Architex.server_name() do
        case Repo.one(from a in Account, where: a.localpart == ^localpart) do
          %Account{displayname: displayname, avatar_url: avatar_url} ->
            data = %{}

            data =
              if field == "displayname" or (field == nil and displayname != nil),
                do: Map.put(data, :displayname, displayname),
                else: data

            data =
              if field == "avatar_url" or (field == nil and avatar_url != nil),
                do: Map.put(data, :avatar_url, avatar_url),
                else: data

            conn
            |> put_status(200)
            |> json(data)

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
