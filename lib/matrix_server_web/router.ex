defmodule MatrixServerWeb.Router do
  use MatrixServerWeb, :router

  alias MatrixServerWeb.Plug.Authenticate

  pipeline :public do
    plug :accepts, ["json"]
  end

  pipeline :authenticate_client do
    plug :accepts, ["json"]
    plug Authenticate
  end

  pipeline :authenticate_server do
    plug :accepts, ["json"]
    # TODO: Add plug to verify peer.
  end

  scope "/_matrix", MatrixServerWeb do
    pipe_through :public

    scope "/client", Client do
      scope "/r0" do
        post "/register", RegisterController, :register
        get "/register/available", AccountController, :available
        get "/login", LoginController, :login_types
        post "/login", LoginController, :login
      end

      get "/versions", InfoController, :versions
    end

    scope "/key/v2", Federation do
      get "/server", KeyController, :get_signing_keys
    end
  end

  scope "/_matrix", MatrixServerWeb.Client do
    pipe_through :authenticate_client

    scope "/client/r0" do
      get "/account/whoami", AccountController, :whoami
      post "/logout", AccountController, :logout
      post "/logout/all", AccountController, :logout_all
      post "/createRoom", RoomController, :create

      scope "/directory/room" do
        put "/:alias", AliasesController, :create
      end
    end
  end

  scope "/_matrix", MatrixServerWeb.Federation do

  end

  scope "/", MatrixServerWeb.Client do
    match :*, "/*path", InfoController, :unrecognized
  end
end
