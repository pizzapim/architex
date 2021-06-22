defmodule MatrixServerWeb.Router do
  use MatrixServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MatrixServerWeb do
    pipe_through :api
  end
end
