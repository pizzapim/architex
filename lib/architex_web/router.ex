defmodule ArchitexWeb.Router do
  use ArchitexWeb, :router

  alias ArchitexWeb.Client.Plug.AuthenticateClient

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
  scope "/_matrix/client", ArchitexWeb.Client do
    pipe_through :public

    scope "/r0" do
      get "/directory/list/room/:room_id", RoomDirectoryController, :get_visibility

      scope "/login" do
        get "/", LoginController, :login_types
        post "/", LoginController, :login
      end

      scope "/register" do
        post "/", RegisterController, :register
        get "/available", AccountController, :available
      end

      scope "/profile/:user_id" do
        get "/", ProfileController, :profile
        get "/avatar_url", ProfileController, :get_avatar_url
        get "/displayname", ProfileController, :get_displayname
      end
    end

    get "/versions", InfoController, :versions
  end

  # Public federation endpoint.
  scope "/_matrix", ArchitexWeb.Federation do
    scope "/key/v2" do
      get "/server", KeyController, :get_signing_keys
    end
  end

  # Authenticated client endpoint.
  scope "/_matrix/client", ArchitexWeb.Client do
    pipe_through :authenticate_client

    scope "/r0" do
      get "/account/whoami", AccountController, :whoami
      post "/createRoom", RoomController, :create
      get "/joined_rooms", RoomController, :joined_rooms
      get "/capabilities", InfoController, :capabilities
      get "/sync", SyncController, :sync

      scope "/logout" do
        post "/", AccountController, :logout
        post "/all", AccountController, :logout_all
      end

      scope "/profile/:user_id" do
        put "/avatar_url", ProfileController, :set_avatar_url
        put "/displayname", ProfileController, :set_displayname
      end

      scope "/directory" do
        put "/room/:alias", AliasesController, :create
        put "/list/room/:room_id", RoomDirectoryController, :set_visibility
      end

      scope "/rooms/:room_id" do
        post "/invite", RoomController, :invite
        post "/join", RoomController, :join
        post "/leave", RoomController, :leave
        post "/kick", RoomController, :kick
        post "/ban", RoomController, :ban
        post "/unban", RoomController, :unban
        put "/send/:event_type/:txn_id", RoomController, :send_message_event
        get "/messages", RoomController, :messages

        scope "/state" do
          get "/", RoomController, :get_state

          scope "/:event_type/*state_key" do
            get "/", RoomController, :get_state_event
            put "/", RoomController, :send_state_event
          end
        end
      end
    end
  end

  # Authenticated federation endpoint.
  scope "/_matrix/federation", ArchitexWeb.Federation do
    pipe_through :authenticate_server

    scope "/v1" do
      get "/query/profile", QueryController, :profile
      get "/event/:event_id", EventController, :event
      get "/state/:room_id", EventController, :state
      get "/state_ids/:room_id", EventController, :state_ids
    end
  end

  scope "/", ArchitexWeb.Client do
    match :*, "/*path", InfoController, :unrecognized
  end
end
