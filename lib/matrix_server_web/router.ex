defmodule MatrixServerWeb.Router do
  use MatrixServerWeb, :router

  alias MatrixServerWeb.Client.Plug.AuthenticateClient

  # TODO: might be able to handle malformed JSON with custom body reader:
  # https://elixirforum.com/t/write-malformed-json-in-the-body-plug/30578/13

  # TODO: Split endpoint into client and federation?

  pipeline :public do
    plug :accepts, ["json"]
  end

  pipeline :authenticate_client do
    plug :accepts, ["json"]
    plug AuthenticateClient
  end

  pipeline :authenticate_server do
    plug :accepts, ["json"]
  end

  # Public client endpoint.
  scope "/_matrix/client", MatrixServerWeb.Client do
    pipe_through :public

    scope "/r0" do
      post "/register", RegisterController, :register
      get "/register/available", AccountController, :available
      get "/login", LoginController, :login_types
      post "/login", LoginController, :login
    end

    get "/versions", InfoController, :versions
  end

  # Public federation endpoint.
  scope "/_matrix", MatrixServerWeb.Federation do
    scope "/key/v2" do
      get "/server", KeyController, :get_signing_keys
    end
  end

  # Authenticated client endpoint.
  scope "/_matrix/client", MatrixServerWeb.Client do
    pipe_through :authenticate_client

    scope "/r0" do
      get "/account/whoami", AccountController, :whoami
      post "/logout", AccountController, :logout
      post "/logout/all", AccountController, :logout_all
      post "/createRoom", RoomController, :create
      get "/joined_rooms", RoomController, :joined_rooms

      scope "/directory/room" do
        put "/:alias", AliasesController, :create
      end

      scope "/rooms/:room_id" do
        post "/invite", RoomController, :invite
        post "/join", RoomController, :join
        post "/leave", RoomController, :leave
        post "/kick", RoomController, :kick
      end
    end
  end

  # Authenticated federation endpoint.
  scope "/_matrix/federation", MatrixServerWeb.Federation do
    pipe_through :authenticate_server

    scope "/v1" do
      get "/query/profile", QueryController, :profile
      get "/event/:event_id", EventController, :event
      get "/state/:room_id", EventController, :state
      get "/state_ids/:room_id", EventController, :state_ids
    end
  end

  scope "/", MatrixServerWeb.Client do
    match :*, "/*path", InfoController, :unrecognized
  end
end
