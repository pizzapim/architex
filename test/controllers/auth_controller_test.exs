defmodule MatrixServerWeb.AuthControllerTest do
  use MatrixServerWeb.ConnCase

  alias MatrixServerWeb.Endpoint

  describe "register endpoint" do
    test "renders the auth flow when no auth parameter is given", %{conn: conn} do
      conn = post(conn, Routes.auth_path(conn, :register))

      assert %{"flows" => flows, "params" => _} = json_response(conn, 401)
      assert is_list(flows)
    end

    test "registers account with minimal information", %{conn: conn} do
      params = %{
        "username" => "user",
        "password" => "lemmein",
        "auth" => %{"type" => "m.login.dummy"}
      }

      conn = post_json(conn, Routes.auth_path(Endpoint, :register), params)

      user_id = MatrixServer.get_mxid("user")

      assert %{"access_token" => _, "device_id" => _, "user_id" => ^user_id} =
               json_response(conn, 200)
    end
  end
end
