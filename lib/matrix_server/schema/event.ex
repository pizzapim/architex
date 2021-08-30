defmodule MatrixServer.Event do
  use Ecto.Schema

  import Ecto.Query

  alias MatrixServer.{Repo, Room, Event, Account, EncodableMap, KeyServer}
  alias MatrixServer.Types.UserId

  # TODO: Could refactor to also always set prev_events, but not necessary.
  @type t :: %__MODULE__{
          type: String.t(),
          origin_server_ts: integer(),
          state_key: String.t(),
          sender: UserId.t(),
          content: map(),
          prev_events: [String.t()] | nil,
          auth_events: [String.t()],
          unsigned: map() | nil,
          signatures: map() | nil,
          hashes: map() | nil
        }

  @primary_key {:event_id, :string, []}
  schema "events" do
    field :type, :string
    field :origin_server_ts, :integer
    field :state_key, :string
    field :sender, UserId
    field :content, :map
    field :prev_events, {:array, :string}
    field :auth_events, {:array, :string}
    field :unsigned, :map
    field :signatures, {:map, {:map, :string}}
    field :hashes, {:map, :string}

    belongs_to :room, Room, type: :string
  end

  defimpl Jason.Encoder, for: Event do
    @pdu_keys [
      :auth_events,
      :content,
      :depth,
      :hashes,
      :origin,
      :origin_server_ts,
      :prev_events,
      :redacts,
      :room_id,
      :sender,
      :signatures,
      :state_key,
      :type,
      :unsigned
    ]

    def encode(event, opts) do
      event
      |> Map.take(@pdu_keys)
      |> Map.update!(:sender, &Kernel.to_string/1)
      |> Jason.Encode.map(opts)
    end
  end

  @spec new(Room.t(), Account.t()) :: %Event{}
  def new(%Room{id: room_id}, %Account{localpart: localpart}) do
    %Event{
      room_id: room_id,
      sender: %UserId{localpart: localpart, domain: MatrixServer.server_name()},
      origin_server_ts: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
      prev_events: [],
      auth_events: []
    }
  end

  @spec is_control_event(t()) :: boolean()
  def is_control_event(%Event{type: "m.room.power_levels", state_key: ""}), do: true
  def is_control_event(%Event{type: "m.room.join_rules", state_key: ""}), do: true

  def is_control_event(%Event{
        type: "m.room.member",
        state_key: state_key,
        sender: sender,
        content: %{membership: membership}
      }) do
    to_string(sender) != state_key and membership in ["leave", "ban"]
  end

  def is_control_event(_), do: false

  @spec is_state_event(t()) :: boolean()
  def is_state_event(%Event{state_key: state_key}), do: state_key != nil

  # Perform validations that can be done before state resolution.
  # For example checking the domain of the sender.
  # We assume that required keys, as well as in the content, is already validated.

  # Rule 1.4 is left to changeset validation.
  @spec prevalidate(t()) :: boolean()
  def prevalidate(%Event{
        type: "m.room.create",
        prev_events: prev_events,
        auth_events: auth_events,
        room_id: room_id,
        sender: %UserId{domain: domain}
      }) do
    # TODO: error check on domains?
    # TODO: rule 1.3

    # Check rules: 1.1, 1.2
    prev_events == [] and
      auth_events == [] and
      domain == MatrixServer.get_domain(room_id)
  end

  def prevalidate(%Event{auth_events: auth_event_ids, prev_events: prev_event_ids} = event) do
    prev_events =
      Event
      |> where([e], e.event_id in ^prev_event_ids)
      |> Repo.all()

    auth_events =
      Event
      |> where([e], e.event_id in ^auth_event_ids)
      |> Repo.all()

    state_pairs = Enum.map(auth_events, &{&1.type, &1.state_key})

    # Check rules: 2.1, 2.2, 3
    length(auth_events) == length(auth_event_ids) and
      length(prev_events) == length(prev_event_ids) and
      not MatrixServer.has_duplicates?(state_pairs) and
      valid_auth_events?(event, auth_events) and
      Enum.find_value(state_pairs, &(&1 == {"m.room.create", ""})) and
      do_prevalidate(event, auth_events, prev_events)
  end

  # Rule 4.1 is left to changeset validation.
  @spec do_prevalidate(t(), [t()], [t()]) :: boolean()
  defp do_prevalidate(
         %Event{type: "m.room.aliases", sender: %UserId{domain: domain}, state_key: state_key},
         _,
         _
       ) do
    # Check rule: 4.2
    domain == MatrixServer.get_domain(state_key)
  end

  # Rule 5.1 is left to changeset validation.
  # Rules 5.2.3, 5.2.4, 5.2.5 is left to state resolution.
  # Check rule: 5.2.1
  defp do_prevalidate(
         %Event{
           type: "m.room.member",
           content: %{"membership" => "join"},
           sender: %UserId{localpart: localpart, domain: domain}
         },
         _,
         [%Event{type: "m.room.create", state_key: %UserId{localpart: localpart, domain: domain}}]
       ),
       do: true

  # Check rule: 5.2.2
  defp do_prevalidate(
         %Event{
           type: "m.room.member",
           content: %{"membership" => "join"},
           sender: sender,
           state_key: state_key
         },
         _,
         _
       ) do
    to_string(sender) == state_key
  end

  # All other rules will be checked during state resolution.
  defp do_prevalidate(_, _, _), do: true

  @spec valid_auth_events?(t(), [t()]) :: boolean()
  defp valid_auth_events?(
         %Event{type: type, sender: sender, state_key: state_key, content: content},
         auth_events
       ) do
    sender = to_string(sender)

    Enum.all?(auth_events, fn
      %Event{type: "m.room.create", state_key: ""} ->
        true

      %Event{type: "m.room.power_levels", state_key: ""} ->
        true

      %Event{type: "m.room.member", state_key: ^sender} ->
        true

      %Event{type: auth_type, state_key: auth_state_key} ->
        if type == "m.room.member" do
          %{"membership" => membership} = content

          (auth_type == "m.room.member" and auth_state_key == state_key) or
            (membership in ["join", "invite"] and auth_type == "m.room.join_rules" and
               auth_state_key == "") or
            (membership == "invite" and auth_type == "m.room.third_party_invite" and
               auth_state_key == "")
        else
          false
        end
    end)
  end

  @spec calculate_content_hash(t()) :: {:ok, binary()} | {:error, Jason.EncodeError.t()}
  defp calculate_content_hash(event) do
    m =
      event
      |> MatrixServer.to_serializable_map()
      |> Map.drop([:unsigned, :signature, :hashes])
      |> EncodableMap.from_map()

    with {:ok, json} <- Jason.encode(m) do
      {:ok, :crypto.hash(:sha256, json)}
    end
  end

  @spec redact(t()) :: map()
  defp redact(%Event{type: type, content: content} = event) do
    redacted_event =
      event
      |> MatrixServer.to_serializable_map()
      |> Map.take([
        :event_id,
        :type,
        :room_id,
        :sender,
        :state_key,
        :content,
        :hashes,
        :signatures,
        :depth,
        :prev_events,
        :prev_state,
        :auth_events,
        :origin,
        :origin_server_ts,
        :membership
      ])

    %{redacted_event | content: redact_content(type, content)}
  end

  @spec redact_content(String.t(), map()) :: map()
  defp redact_content("m.room.member", content), do: Map.take(content, ["membership"])
  defp redact_content("m.room.create", content), do: Map.take(content, ["creator"])
  defp redact_content("m.room.join_rules", content), do: Map.take(content, ["join_rule"])
  defp redact_content("m.room.aliases", content), do: Map.take(content, ["aliases"])

  defp redact_content("m.room.history_visibility", content),
    do: Map.take(content, ["history_visibility"])

  defp redact_content("m.room.power_levels", content),
    do:
      Map.take(content, [
        "ban",
        "events",
        "events_default",
        "kick",
        "redact",
        "state_default",
        "users",
        "users_default"
      ])

  defp redact_content(_, _), do: %{}

  # Adds content hash, adds signature and calculates event id.
  @spec post_process(t()) :: {:ok, t()} | :error
  def post_process(event) do
    with {:ok, content_hash} <- calculate_content_hash(event) do
      encoded_hash = MatrixServer.encode_unpadded_base64(content_hash)
      event = %Event{event | hashes: %{"sha256" => encoded_hash}}

      with {:ok, sig, key_id} <- KeyServer.sign_object(redact(event)) do
        event = %Event{event | signatures: %{MatrixServer.server_name() => %{key_id => sig}}}

        with {:ok, event} <- set_event_id(event) do
          {:ok, event}
        else
          _ -> :error
        end
      end
    else
      _ -> :error
    end
  end

  @spec set_event_id(t()) :: {:ok, t()} | {:error, Jason.EncodeError.t()}
  def set_event_id(event) do
    with {:ok, event_id} <- generate_event_id(event) do
      {:ok, %Event{event | event_id: event_id}}
    end
  end

  @spec generate_event_id(t()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  defp generate_event_id(event) do
    with {:ok, hash} <- calculate_reference_hash(event) do
      {:ok, "$" <> MatrixServer.encode_url_safe_base64(hash)}
    end
  end

  @spec calculate_reference_hash(t()) :: {:ok, binary()} | {:error, Jason.EncodeError.t()}
  defp calculate_reference_hash(event) do
    redacted_event =
      event
      |> redact()
      |> Map.drop([:unsigned, :signature, :age_ts])

    with {:ok, json} <- MatrixServer.encode_canonical_json(redacted_event) do
      {:ok, :crypto.hash(:sha256, json)}
    end
  end
end
