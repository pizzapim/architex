defmodule MatrixServerWeb.Router do
  use MatrixServerWeb, :router

  pipeline :public do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug :accepts, ["json"]
    plug MatrixServerWeb.Authenticate
  end

  scope "/_matrix", MatrixServerWeb do
    pipe_through :public

    scope "/client/r0", as: :client do
      post "/register", AuthController, :register
      get "/login", AuthController, :login
      get "/register/available", AccountController, :available
    end

    get "/client/versions", InfoController, :versions
  end

  scope "/_matrix", MatrixServerWeb do
    pipe_through :authenticated

    scope "/client/r0", as: :client do
      get "/account/whoami", AccountController, :whoami
    end
  end
end
