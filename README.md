# Architex

A Matrix homeserver written in Elixir.
Currently, this project is in a very early stage.

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

TODO: list implemented endpoints

### Implemented

* State resolution: functional, but very memory-intensive and with high database usage. For now it is sufficient, but snapshots should be used in the future. See: [State Resolution v2 for the Hopelessly Unmathematical](https://matrix.org/docs/guides/implementing-stateres), [State Resolution: Reloaded](https://matrix.uhoreg.ca/stateres/reloaded.html) and [Room Version 2](https://spec.matrix.org/unstable/rooms/v2).
* Authorization rules ([Room version 1](https://spec.matrix.org/unstable/rooms/v1/))
* Homeserver authentication using signing keys ([4.1 Request Authentication](https://matrix.org/docs/spec/server_server/latest#request-authentication))
* Client authentication ([5.1 Using access tokens](https://matrix.org/docs/spec/client_server/r0.6.1#using-access-tokens))

### Major unimplemented features

* Resolving server names (but works for local development) ([3.1 Resolving server names](https://matrix.org/docs/spec/server_server/latest#resolving-server-names))
* Checks when receiving events via federation (i.e. valid format, signature check and hash check) ([6.1 Checks performed on receipt of a PDU](https://matrix.org/docs/spec/server_server/latest#checks-performed-on-receipt-of-a-pdu))
* Federation of events
