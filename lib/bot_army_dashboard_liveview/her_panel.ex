defmodule BotArmyDashboardLiveview.HerPanel do
  @moduledoc """
  Where her own control panel is — one place that knows, for every screen here that
  has to point at it.

  The household runs two instances of one wife-care release: the authority's panel
  and hers. This dashboard is the phone she carries, so when it points anywhere it
  points at *hers*. That address was written into the house screen alone until this
  module existed, which was fine while one screen pointed at it and wrong the moment
  a second one did — the retirement map now sends a bookmarked wardrobe address
  across to her closet, and two copies of a host and a port are two places to forget.

  ## The host is this request's host, and that is the whole point

  From a phone or a second machine, `localhost` is the *viewer's* machine, where no
  panel runs. A link built that way is how a working panel came to look like one that
  did not exist. So both entry points take the host the surface was reached on:
  `url/1` from a LiveView's `socket.host_uri`, `url_from_host/1` from a Plug
  connection's `host` string. A request that arrived with no usable host falls back
  to `localhost`, which is right when the surface *is* localhost and merely useless
  otherwise — and useless is the honest failure for a link, where raising would take
  down the screen that was only trying to point somewhere.

  ## `WIFE_CARE_CONTROL_PANEL_URL` overrides both

  For a deployment where the panel is reached under a name or a proxy the dashboard
  cannot infer from the request it got. It replaces host *and* port together, because
  a value that only replaced the port could not express `https://…`.
  """

  # The panel's port on this household's machines. `docs/wife_care/PANELS.md` in the
  # elixir_bots monorepo has the three-surface map, and the 30014 row is this one.
  @port 30014

  # The closet group inside her panel. A group has an address there (§39 of the bot's
  # control surface contract), which is what lets a retired path hand a bookmark to the
  # screen it was really about rather than to the panel's front door.
  @closet "/?tab=closet"

  @doc "Her panel's base URL, off the host this request arrived on."
  @spec url(URI.t() | nil) :: String.t()
  def url(%URI{} = host_uri), do: base(host_of(host_uri))
  def url(_host_uri), do: base("localhost")

  @doc "The same, for a Plug connection, which carries a host string and no URI."
  @spec url_from_host(String.t() | nil) :: String.t()
  def url_from_host(host) when is_binary(host) and host != "", do: base(host)
  def url_from_host(_host), do: base("localhost")

  @doc "Her closet inside that panel, as an absolute URL — a different origin, so it must be one."
  @spec closet_url(URI.t() | nil) :: String.t()
  def closet_url(host_uri), do: url(host_uri) <> @closet

  @doc "The same, for a Plug connection."
  @spec closet_url_from_host(String.t() | nil) :: String.t()
  def closet_url_from_host(host), do: url_from_host(host) <> @closet

  defp base(host) do
    System.get_env("WIFE_CARE_CONTROL_PANEL_URL") || "http://#{host}:#{@port}"
  end

  defp host_of(%URI{host: host}) when is_binary(host) and host != "", do: host
  defp host_of(_host_uri), do: "localhost"
end
