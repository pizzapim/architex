defmodule ArchitexWeb.RegisterControllerTest do
  use ArchitexWeb.ConnCase

  import Ecto.Query

  alias Architex.{Repo, Device, Factory}
  alias ArchitexWeb.Endpoint

  @basic_params %{
    "username" => "user",
    "password" => "lemmein",
    "auth" => %{"type" => "m.login.dummy"}
  }

  describe "register endpoint" do
    test "renders the auth flow when no auth parameter is given", %{conn: conn} do
      conn = post(conn, Routes.register_path(conn, :register))

      assert %{"flows" => flows, "params" => _} = json_response(conn, 401)
      assert is_list(flows)
    end

    test "registers account with minimal information", %{conn: conn} do
      conn = post_json(conn, Routes.register_path(Endpoint, :register), @basic_params)
      user_id = Architex.get_mxid("user")

      assert %{"access_token" => _, "device_id" => _, "user_id" => ^user_id} =
               json_response(conn, 200)
    end

    test "registers and sets device id", %{conn: conn} do
      params = Map.put(@basic_params, :device_id, "android")
      conn = post_json(conn, Routes.register_path(Endpoint, :register), params)

      assert %{"device_id" => "android"} = json_response(conn, 200)
    end

    test "registers and sets display name", %{conn: conn} do
      params = Map.put(@basic_params, :initial_device_display_name, "My Android")
      conn = post_json(conn, Routes.register_path(Endpoint, :register), params)

      assert json_response(conn, 200)
      assert Repo.one!(from d in Device, select: d.display_name) == "My Android"
    end

    test "rejects account if localpart is already in use", %{conn: conn} do
      Factory.insert(:account, localpart: "sneed")

      conn =
        post_json(conn, Routes.register_path(Endpoint, :register), %{
          @basic_params
          | "username" => "sneed"
        })

      assert %{"errcode" => "M_USER_IN_USE"} = json_response(conn, 400)
    end

    test "obeys inhibit_login parameter", %{conn: conn} do
      params = Map.put(@basic_params, :inhibit_login, "true")
      conn = post_json(conn, Routes.register_path(Endpoint, :register), params)

      assert response = json_response(conn, 200)
      refute Map.has_key?(response, "access_token")
      refute Map.has_key?(response, "device_id")
    end

    test "generates localpart if omitted", %{conn: conn} do
      params = Map.delete(@basic_params, "username")
      conn = post_json(conn, Routes.register_path(Endpoint, :register), params)

      assert %{"user_id" => _} = json_response(conn, 200)
    end

    test "rejects invalid usernames", %{conn: conn} do
      conn =
        post_json(conn, Routes.register_path(Endpoint, :register), %{
          @basic_params
          | "username" => "User1"
        })

      assert %{"errcode" => "M_INVALID_USERNAME"} = json_response(conn, 400)
    end
  end
end
