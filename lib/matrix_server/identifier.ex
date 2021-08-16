defmodule MatrixServer.Identifier do
  use Ecto.Type

  alias MatrixServer.Identifier

  defstruct [:type, :localpart, :domain]

  def type(), do: :string

  def cast(id) when is_binary(id) do
    with %Identifier{} = identifier <- parse(id) do
      {:ok, identifier}
    end
  end

  def cast(_), do: :error

  defp parse(id) do
    {sigil, id} = String.split_at(id, 1)

    case get_type(sigil) do
      {:ok, :event} ->
        parse_event(id)

      {:ok, type} when type in [:user, :room, :group, :alias] ->
        case String.split(id, ":", parts: 2) do
          [localpart, domain] ->
            case type do
              :user -> parse_user(localpart, domain)
              :room -> parse_room(localpart, domain)
              :group -> parse_group(localpart, domain)
              :alias -> parse_alias(localpart, domain)
            end

          _ ->
            :error
        end

      :error ->
        :error
    end
  end

  defp get_type("@"), do: {:ok, :user}
  defp get_type("!"), do: {:ok, :room}
  defp get_type("$"), do: {:ok, :event}
  defp get_type("+"), do: {:ok, :group}
  defp get_type("#"), do: {:ok, :alias}
  defp get_type(_), do: :error

  @user_regex ~r/^[a-z0-9._=\-\/]+$/
  defp parse_user(localpart, domain) do
    if String.length(localpart) + String.length(domain) + 2 <= 255 and
         Regex.match?(@user_regex, localpart) and
         valid_domain?(domain) do
      %Identifier{type: :user, localpart: localpart, domain: domain}
    else
      :error
    end
  end

  defp parse_room(localpart, domain) do
    if valid_domain?(domain) do
      %Identifier{type: :room, localpart: localpart, domain: domain}
    else
      :error
    end
  end

  @event_regex ~r/^[[:alnum:]-_]+$/
  defp parse_event(localpart) do
    if Regex.match?(@event_regex, localpart) do
      %Identifier{type: :event, localpart: localpart}
    else
      :error
    end
  end

  @group_regex ~r/^[[:lower:][:digit:]._=\-\/]+$/
  defp parse_group(localpart, domain) do
    if String.length(localpart) + String.length(domain) + 2 <= 255 and
         Regex.match?(@group_regex, localpart) and
         valid_domain?(domain) do
      %Identifier{type: :group, localpart: localpart, domain: domain}
    else
      :error
    end
  end

  defp parse_alias(localpart, domain) do
    if String.length(localpart) + String.length(domain) + 2 <= 255 and valid_domain?(domain) do
      %Identifier{type: :alias, localpart: localpart, domain: domain}
    else
      :error
    end
  end

  def load(id) when is_binary(id) do
    {:ok, parse_unvalidated(id)}
  end

  def load(_), do: :error

  defp parse_unvalidated(id) do
    {sigil, id} = String.split_at(id, 1)

    case get_type(sigil) do
      {:ok, :event} ->
        %Identifier{type: :event, localpart: id}

      {:ok, type} ->
        [localpart, domain] = String.split(id, ":", parts: 2)

        identifier = %Identifier{localpart: localpart, domain: domain}

        case type do
          :user -> %Identifier{identifier | type: :user}
          :room -> %Identifier{identifier | type: :room}
          :group -> %Identifier{identifier | type: :group}
          :alias -> %Identifier{identifier | type: :alias}
        end
    end
  end

  def dump(%Identifier{type: :event, localpart: localpart}) do
    {:ok, "$" <> localpart}
  end

  def dump(%Identifier{type: type, localpart: localpart, domain: domain}) do
    {:ok, type_to_sigil(type) <> localpart <> ":" <> domain}
  end

  def dump(_), do: :error

  defp type_to_sigil(:user), do: "@"
  defp type_to_sigil(:room), do: "!"
  defp type_to_sigil(:event), do: "$"
  defp type_to_sigil(:group), do: "+"
  defp type_to_sigil(:alias), do: "#"

  @ipv6_regex ~r/^\[(?<ip>[^\]]+)\](?<port>:\d{1,5})?$/
  @ipv4_regex ~r/^(?<hostname>[^:]+)(?<port>:\d{1,5})?$/
  @dns_regex ~r/^[[:alnum:]-.]{1,255}$/
  defp valid_domain?(domain) do
    if String.starts_with?(domain, "[") do
      # Parse as ipv6.
      with %{"ip" => ip} <-
             Regex.named_captures(@ipv6_regex, domain),
           {:ok, _} <- :inet.parse_address(String.to_charlist(ip)) do
        true
      else
        _ -> false
      end
    else
      # Parse as ipv4 or dns name.
      case Regex.named_captures(@ipv4_regex, domain) do
        nil ->
          false

        %{"hostname" => hostname} ->
          # Try to parse as ipv4.
          case String.to_charlist(hostname) |> :inet.parse_address() do
            {:ok, _} ->
              true

            {:error, _} ->
              # Try to parse as dns name.
              Regex.match?(@dns_regex, hostname)
          end
      end
    end
  end
end
