# Matrix homeserver

This is my attempt at creating a Matrix homeserver in Elixir.
Currently it is in a very early stage.

Some noteworthy contributions:

* `lib/matrix_server/state_resolution.ex`: Implementation of version 2 of the Matrix state resolution algorithm.
* `lib/matrix_server/state_resolution/authorization.ex`: Implementation of authorization rules for the state resolution algorithm.
* `lib/matrix_server/room_server.ex`: A GenServer that holds and manages the state of a room.

To run the server in development mode, run:

* Install the latest Erlang, Elixir and Postgresql.
* Create the database with name `matrix_server_dev` and credentials `matrix_server:matrix_server`.
* Fetch Elixir dependencies with `mix deps.get`.
* Run the server using `mix phx.server`.
