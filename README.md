# Architex

A Matrix homeserver written in Elixir.
Currently, this project is in a very early stage.

## General architecture

For each room that a homeserver is involved in, there is a supervised GenServer (named [RoomServer](lib/architex/room_server.ex)) that holds/manages the room's state.
These RoomServers are responsible for state resolution and authorization.
Database schemas are located at [lib/architex/schema/](lib/architex/schema/).
Requests from the federation API as well as the client API are validated using [Ecto](https://hex.pm/packages/ecto)'s `embedded_schema`s, located at [lib/architex_web/api_schemas/](lib/architex_web/api_schemas/).

## Noteworthy contributions

* `lib/architex/state_resolution.ex`: Implementation of version 2 of the Matrix state resolution algorithm.
* `lib/architex/state_resolution/authorization.ex`: Implementation of authorization rules for the state resolution algorithm.
* `lib/architex/room_server.ex`: A GenServer that holds and manages the state of a room.

## Dependencies

* Elixir 1.12.2 compiled for OTP 24
* Erlang 24.0.3
* PostgreSQL
* Libsodium


Generate the server's ed25519 keys by executing `ssh-keygen -t ed25519 -f keys/id_ed25519 -N ""`

## Progress

Here, implemented and some unimplemented features are listed.

### Implemented features

* State resolution: functional, but very memory-intensive and with high database usage. For now it is sufficient, but snapshots should be used in the future. See: [State Resolution v2 for the Hopelessly Unmathematical](https://matrix.org/docs/guides/implementing-stateres), [State Resolution: Reloaded](https://matrix.uhoreg.ca/stateres/reloaded.html) and [Room Version 2](https://spec.matrix.org/unstable/rooms/v2).
* Authorization rules ([Room version 1](https://spec.matrix.org/unstable/rooms/v1/))
* Homeserver authentication using signing keys ([4.1 Request Authentication](https://matrix.org/docs/spec/server_server/latest#request-authentication))
* Client authentication ([5.1 Using access tokens](https://matrix.org/docs/spec/client_server/r0.6.1#using-access-tokens))

### Implemented API endpoints

#### Client-Server API

- GET /_matrix/client/r0/register/available
- GET /_matrix/client/r0/account/whoami
- POST /_matrix/client/r0/logout
- POST /_matrix/client/r0/logout/all
- PUT /_matrix/client/r0/directory/room/{roomAlias}
- GET /_matrix/client/versions
- GET /_matrix/client/r0/login
- POST /_matrix/client/r0/login: Only with password flow.
- POST /_matrix/client/r0/register: Only with dummy flow.
- POST /_matrix/client/r0/createRoom: Except with option invite_3pid.
- GET /_matrix/client/r0/joined_rooms
- POST /_matrix/client/r0/rooms/{roomId}/invite
- POST /_matrix/client/r0/rooms/{roomId}/join: Except with third party invite.
- POST /_matrix/client/r0/rooms/{roomId}/leave
- POST /_matrix/client/r0/rooms/{roomId}/kick
- POST /_matrix/client/r0/rooms/{roomId}/ban
- POST /_matrix/client/r0/rooms/{roomId}/unban
- PUT /_matrix/client/r0/rooms/{roomId}/state/{eventType}/{stateKey}
- PUT /_matrix/client/r0/rooms/{roomId}/send/{eventType}/{txnId}
- GET /_matrix/client/r0/rooms/{roomId}/messages: Except filtering.
- GET /_matrix/client/r0/directory/list/room/{roomId}
- PUT /_matrix/client/r0/directory/list/room/{roomId}
- GET /_matrix/client/r0/capabilities
- GET /_matrix/client/r0/profile/{userId}
- GET /_matrix/client/r0/profile/{userId}/avatar_url
- PUT /_matrix/client/r0/profile/{userId}/avatar_url
- GET /_matrix/client/r0/profile/{userId}/displayname
- PUT /_matrix/client/r0/profile/{userId}/displayname

#### Federation API

- GET /_matrix/federation/v1/event/{eventId}
- GET /_matrix/federation/v1/state/{roomId}
- GET /_matrix/federation/v1/state_ids/{roomId}
- GET /_matrix/key/v2/server/{keyId}
- GET /_matrix/federation/v1/query/profile: Except displayname and avatar_url is not implemented.

### Major unimplemented features

* Resolving server names (but works for local development) ([3.1 Resolving server names](https://matrix.org/docs/spec/server_server/latest#resolving-server-names))
* Checks when receiving events via federation (i.e. valid format, signature check and hash check) ([6.1 Checks performed on receipt of a PDU](https://matrix.org/docs/spec/server_server/latest#checks-performed-on-receipt-of-a-pdu))
* Federation of events
