defmodule MatrixServerWeb.Router do
  use MatrixServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/_matrix", MatrixServerWeb do
    pipe_through :api

    scope "/client/r0", as: :client do
      post "/register", AuthController, :register
      get "/login", AuthController, :login
      get "/register/available", AccountController, :available
    end

    get "/client/versions", InfoController, :versions
  end
end
