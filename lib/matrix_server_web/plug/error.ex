defmodule MatrixServerWeb.Plug.Error do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @error_code_and_message %{
    bad_json: {400, "M_BAD_JSON", "Bad request."},
    user_in_use: {400, "M_USE_IN_USE", "Username is already taken."},
    invalid_username: {400, "M_INVALID_USERNAME", "Invalid username."},
    forbidden: {400, "M_FORBIDDEN", "The requested action is forbidden."},
    unrecognized: {400, "M_UNRECOGNIZED", "Unrecognized request."},
    unknown: {400, "M_UNKNOWN", "An unknown error occurred."},
    unknown_token: {401, "M_UNKNOWN_TOKEN", "Invalid access token."},
    missing_token: {401, "M_MISSING_TOKEN", "Access token required."}
  }

  def put_error(conn, error) do
    {status, errcode, errmsg} = @error_code_and_message[error]
    data = %{errcode: errcode, error: errmsg}

    conn
    |> put_status(status)
    |> json(data)
    |> halt()
  end
end
