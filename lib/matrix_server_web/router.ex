defmodule MatrixServerWeb.Router do
  use MatrixServerWeb, :router

  alias MatrixServerWeb.Plug.Authenticate

  pipeline :public do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug :accepts, ["json"]
    plug Authenticate
  end

  scope "/_matrix", MatrixServerWeb do
    pipe_through :public

    scope "/client/r0", as: :client do
      post "/register", AuthController, :register
      get "/register/available", AccountController, :available
      get "/login", AuthController, :login_types
      post "/login", AuthController, :login
    end

    get "/client/versions", InfoController, :versions
  end

  scope "/_matrix", MatrixServerWeb do
    pipe_through :authenticated

    scope "/client/r0", as: :client do
      get "/account/whoami", AccountController, :whoami
      post "/logout", AccountController, :logout
      post "/logout/all", AccountController, :logout_all
      post "/createRoom", RoomController, :create
    end
  end

  scope "/", MatrixServerWeb do
    match :*, "/*path", InfoController, :unrecognized
  end
end
