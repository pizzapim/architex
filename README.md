# Matrix homeserver

This is my attempt at creating a Matrix homeserver in Elixir.
Currently it is in a very early stage.

Some noteworthy contributions:

* `lib/matrix_server/state_resolution.ex`: Implementation of version 2 of the Matrix state resolution algorithm.
* `lib/matrix_server/state_resolution/authorization.ex`: Implementation of authorization rules for the state resolution algorithm.
* `lib/matrix_server/room_server.ex`: A GenServer that holds and manages the state of a room.

Generate the server's ed25510 keys by executing `ssh-keygen -t ed25519 -f keys/id_ed25519 -N ""`

Dependencies:

* Elixir 1.12.2 compiled for OTP 24
* Erlang 24.0.3
* PostgreSQL
* Libsodium
