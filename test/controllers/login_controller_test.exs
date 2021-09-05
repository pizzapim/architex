defmodule ArchitexWeb.LoginControllerTest do
  use ArchitexWeb.ConnCase

  alias Architex.Factory
  alias ArchitexWeb.Endpoint

  @basic_params %{
    "type" => "m.login.password",
    "identifier" => %{
      "type" => "m.id.user",
      "user" => "sneed"
    },
    "password" => "lemmein"
  }

  describe "login endpoint" do
    test "renders the list of login types", %{conn: conn} do
      conn = get(conn, Routes.login_path(Endpoint, :login))

      assert %{"flows" => flows} = json_response(conn, 200)
      assert is_list(flows)
    end

    test "logs a user in with password and matrix user id", %{conn: conn} do
      Factory.insert(:account, localpart: "sneed", password_hash: Bcrypt.hash_pwd_salt("lemmein"))
      conn = post_json(conn, Routes.login_path(Endpoint, :login), @basic_params)

      assert %{"user_id" => _, "access_token" => _, "device_id" => _} = json_response(conn, 200)

      conn =
        recycle(conn)
        |> post_json(Routes.login_path(Endpoint, :login), %{
          @basic_params
          | "identifier" => %{"type" => "m.id.user", "user" => Architex.get_mxid("sneed")}
        })

      assert %{"user_id" => _, "access_token" => _, "device_id" => _} = json_response(conn, 200)
    end

    test "handles unknown matrix user id", %{conn: conn} do
      conn = post_json(conn, Routes.login_path(Endpoint, :login), @basic_params)

      assert %{"errcode" => "M_FORBIDDEN"} = json_response(conn, 403)
    end

    test "handles wrong password", %{conn: conn} do
      Factory.insert(:account, localpart: "sneed", password_hash: Bcrypt.hash_pwd_salt("surprise"))

      conn = post_json(conn, Routes.login_path(Endpoint, :login), @basic_params)

      assert %{"errcode" => "M_FORBIDDEN"} = json_response(conn, 403)
    end

    # TODO: Test display name
    # TODO: Test device recycling
  end
end
