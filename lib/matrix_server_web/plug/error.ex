defmodule MatrixServerWeb.Plug.Error do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @error_map %{
    bad_json: {400, "M_BAD_JSON", "Bad request."},
    user_in_use: {400, "M_USER_IN_USE", "Username is already taken."},
    invalid_username: {400, "M_INVALID_USERNAME", "Invalid username."},
    forbidden: {400, "M_FORBIDDEN", "The requested action is forbidden."},
    unrecognized: {400, "M_UNRECOGNIZED", "Unrecognized request."},
    unknown: {400, "M_UNKNOWN", "An unknown error occurred."},
    invalid_room_state:
      {400, "M_INVALID_ROOM_STATE", "The request would leave the room in an invalid state."},
    unauthorized: {400, "M_UNAUTHORIZED", "The request was unauthorized."},
    unknown_token: {401, "M_UNKNOWN_TOKEN", "Invalid access token."},
    missing_token: {401, "M_MISSING_TOKEN", "Access token required."},
    not_found: {404, "M_NOT_FOUND", "The requested resource was not found."},
    room_alias_exists: {409, "M_UNKNOWN", "The given room alias already exists."}
  }

  def put_error(conn, {error, msg}), do: put_error(conn, error, msg)

  def put_error(conn, error, msg \\ nil) do
    {status, errcode, default_msg} = @error_map[error]
    data = %{errcode: errcode, error: msg || default_msg}

    conn
    |> put_status(status)
    |> json(data)
    |> halt()
  end
end
