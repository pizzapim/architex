defmodule MatrixServerWeb.AuthControllerTest do
  use MatrixServerWeb.ConnCase

  import Ecto.Query

  alias MatrixServer.{Repo, Device, Factory}
  alias MatrixServerWeb.Endpoint

  @basic_params %{
    "username" => "user",
    "password" => "lemmein",
    "auth" => %{"type" => "m.login.dummy"}
  }

  describe "register endpoint" do
    test "renders the auth flow when no auth parameter is given", %{conn: conn} do
      conn = post(conn, Routes.auth_path(conn, :register))

      assert %{"flows" => flows, "params" => _} = json_response(conn, 401)
      assert is_list(flows)
    end

    test "registers account with minimal information", %{conn: conn} do
      conn = post_json(conn, Routes.auth_path(Endpoint, :register), @basic_params)
      user_id = MatrixServer.get_mxid("user")

      assert %{"access_token" => _, "device_id" => _, "user_id" => ^user_id} =
               json_response(conn, 200)
    end

    test "registers and sets device id", %{conn: conn} do
      params = Map.put(@basic_params, :device_id, "android")
      conn = post_json(conn, Routes.auth_path(Endpoint, :register), params)

      assert %{"device_id" => "android"} = json_response(conn, 200)
    end

    test "registers and sets display name", %{conn: conn} do
      params = Map.put(@basic_params, :initial_device_display_name, "My Android")
      conn = post_json(conn, Routes.auth_path(Endpoint, :register), params)

      assert json_response(conn, 200)
      assert Repo.one!(from d in Device, select: d.display_name) == "My Android"
    end

    test "rejects account if localpart is already in use", %{conn: conn} do
      Factory.insert(:account, localpart: "sneed")

      conn =
        post_json(conn, Routes.auth_path(Endpoint, :register), %{
          @basic_params
          | "username" => "sneed"
        })

      assert %{"errcode" => "M_USER_IN_USE"} = json_response(conn, 400)
    end

    test "obeys inhibit_login parameter", %{conn: conn} do
      params = Map.put(@basic_params, :inhibit_login, "true")
      conn = post_json(conn, Routes.auth_path(Endpoint, :register), params)

      assert response = json_response(conn, 200)
      refute Map.has_key?(response, "access_token")
      refute Map.has_key?(response, "device_id")
    end

    test "generates localpart if omitted", %{conn: conn} do
      params = Map.delete(@basic_params, "username")
      conn = post_json(conn, Routes.auth_path(Endpoint, :register), params)

      assert %{"user_id" => _} = json_response(conn, 200)
    end

    test "rejects invalid usernames", %{conn: conn} do
      conn =
        post_json(conn, Routes.auth_path(Endpoint, :register), %{
          @basic_params
          | "username" => "User1"
        })

      assert %{"errcode" => "M_INVALID_USERNAME"} = json_response(conn, 400)
    end
  end

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
      conn = get(conn, Routes.auth_path(Endpoint, :login))

      assert %{"flows" => flows} = json_response(conn, 200)
      assert is_list(flows)
    end

    test "logs a user in with password and matrix user id", %{conn: conn} do
      Factory.insert(:account, localpart: "sneed", password_hash: Bcrypt.hash_pwd_salt("lemmein"))
      conn = post_json(conn, Routes.auth_path(Endpoint, :login), @basic_params)

      assert %{"user_id" => _, "access_token" => _, "device_id" => _} = json_response(conn, 200)

      conn =
        recycle(conn)
        |> post_json(Routes.auth_path(Endpoint, :login), %{
          @basic_params
          | "identifier" => %{"type" => "m.id.user", "user" => MatrixServer.get_mxid("sneed")}
        })

      assert %{"user_id" => _, "access_token" => _, "device_id" => _} = json_response(conn, 200)
    end

    test "handles unknown matrix user id", %{conn: conn} do
      conn = post_json(conn, Routes.auth_path(Endpoint, :login), @basic_params)

      assert %{"errcode" => "M_FORBIDDEN"} = json_response(conn, 400)
    end

    test "handles wrong password", %{conn: conn} do
      Factory.insert(:account, localpart: "sneed", password_hash: Bcrypt.hash_pwd_salt("surprise"))

      conn = post_json(conn, Routes.auth_path(Endpoint, :login), @basic_params)

      assert %{"errcode" => "M_FORBIDDEN"} = json_response(conn, 400)
    end

    # TODO: Test display name
    # TODO: Test device recycling
  end
end
