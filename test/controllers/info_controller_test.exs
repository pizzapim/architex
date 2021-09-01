defmodule ArchitexWeb.InfoControllerTest do
  use ArchitexWeb.ConnCase

  test "versions endpoint returns a list of supported Matrix spec versions", %{conn: conn} do
    conn = get(conn, Routes.info_path(conn, :versions))

    assert %{"versions" => versions} = json_response(conn, 200)
    assert is_list(versions)
  end

  test "unrecognized route renders M_UNRECOGNIZED error", %{conn: conn} do
    conn = get(conn, ArchitexWeb.Endpoint.url() <> "/sneed")

    assert %{"errcode" => "M_UNRECOGNIZED"} = json_response(conn, 400)
  end
end
