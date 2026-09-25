defmodule BotArmyDashboardLiveview.BotRead do
  @moduledoc """
  One way for a screen to read, so a failed read is never reported as empty.

  Every phone screen used to hand-roll the same thing: ask the broker inside a
  `Task.start_link/1`, decode, and on any failure send an empty list. The screen
  then drew its empty state — "No projects found" — for a bot that had never
  answered. Nothing on that screen was true: the read had not returned *nothing*,
  it had not *returned*.

  Here a read has two outcomes and the screen is told which one happened:

    * the bot answered and the answer decoded — `{tag, value}`
    * it did not — `{:read_failed, reason}`, which `ReadHooks` turns into an
      assign, so the screen says why instead of showing an empty list

  A reply whose *shape* is not what the screen asked for is a failure too
  (`:unexpected_reply`). "The bot answered something else" is a different
  sentence from "there is nothing", and the screens were saying the second one
  for both.
  """

  import Phoenix.Component, only: [assign: 3]

  alias BotArmyDashboardLiveview.Broker

  # The fields a responder wraps around the payload it is answering with. `data`
  # is the payload; the rest is the wrapper's bookkeeping. Measured against what
  # is actually on the wire: `bot_army.registry.bots.list` answers
  # `{"data": {"bots": […]}, "ok": true, "schema_version": "1.0", "timestamp": …}`,
  # so `ok` and `schema_version` have to be here or its bots never unwrap.
  @envelope ~w(data ok error correlation_id timestamp event_type schema_version)

  @doc """
  Ask in a task, and answer the process that asked for it.

  The caller passes its own pid: inside the task `self()` is the task, and a read
  that addresses its own answer there is a read whose answer is thrown away — 88
  of them were, and five screens sat on their spinners forever.

  Nothing is returned: the answer arrives as a message. A task rather than a
  blocking call, because no screen here may hold a render for a broker round trip.
  """
  @spec async(pid(), atom(), String.t(), term(), keyword()) :: :ok
  def async(parent, tag, subject, payload, opts \\ []) do
    Task.start_link(fn ->
      send(parent, {:read_started, tag})
      send(parent, reply(tag, read(subject, payload, opts)))
    end)

    :ok
  end

  @doc """
  Ask now: `{:ok, decoded}` or `{:error, reason}`.

  A `{"data": …}` envelope is unwrapped: some responders wrap their payload and
  some do not, and a screen should not have to know which kind it is talking to.
  """
  @spec read(String.t(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def read(subject, payload, opts \\ []) do
    with {:ok, body} <- encode(payload),
         {:ok, %{body: reply}} <- Broker.request(subject, body, opts),
         {:ok, decoded} <- decode(reply) do
      {:ok, unwrap(decoded)}
    end
  end

  defp reply(tag, {:ok, value}), do: {tag, value}
  defp reply(tag, {:error, reason}), do: {:read_failed, tag, reason}

  defp encode(payload) when is_binary(payload), do: {:ok, payload}

  defp encode(payload) do
    case Jason.encode(payload) do
      {:ok, body} -> {:ok, body}
      {:error, _reason} -> {:error, :bad_payload}
    end
  end

  defp decode(reply) when is_binary(reply) do
    case Jason.decode(reply) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :bad_reply}
    end
  end

  defp decode(_reply), do: {:error, :bad_reply}

  # Only unwrap when `data` is all there is to the reply, apart from the envelope
  # fields a wrapper adds around it: a payload that happens to have a `data` key
  # of its own must survive.
  defp unwrap(%{"data" => data} = reply) do
    if Enum.all?(Map.keys(reply), &(&1 in @envelope)), do: data, else: reply
  end

  defp unwrap(decoded), do: decoded

  @doc """
  Pull a list out of an answer that may carry it under a key, or be the list.

  `bridge.project.list` answers `{"projects": [...]}`; a bot that answers with
  the list itself is answering the same thing. Anything else is `:error`, which
  the caller renders as a refusal: an answer shaped like neither is not an empty
  list, and the screens used to read it as one.
  """
  @spec list(term(), String.t()) :: {:ok, list()} | :error
  def list(answer, _key) when is_list(answer), do: {:ok, answer}

  def list(%{} = answer, key) do
    case Map.get(answer, key) do
      value when is_list(value) -> {:ok, value}
      _other -> :error
    end
  end

  def list(_answer, _key), do: :error

  @doc """
  Mark the screen as having a failed read.

  Called by `ReadHooks` for the `{:read_failed, reason}` message, so no view has
  to carry a clause for it and none can forget one.
  """
  @spec failed(map(), term()) :: map()
  def failed(socket, reason), do: failed(socket, nil, reason)

  @doc """
  The same, naming the read that failed.

  The name matters because a screen can have several reads in flight: without it
  the next read to start erases the failure of the one before it, and the screen
  shows a tidy page for a question that was never answered.
  """
  @spec failed(map(), atom() | nil, term()) :: map()
  def failed(socket, tag, reason) do
    socket
    |> assign(:read_error, message(reason))
    |> assign(:read_failed_tag, tag)
    |> stop_spinners()
    |> mark_broker_unreachable()
  end

  # A screen that shows a NATS badge learns the truth from the same failure: if a
  # read just went unanswered, that badge is not "Offline" because a probe of
  # some subject nothing serves said so — it is offline because the round trip
  # did not come back. Only screens that track one get the assign.
  defp mark_broker_unreachable(socket) do
    if Map.has_key?(socket.assigns, :nats_status) do
      assign(socket, :nats_status, :unhealthy)
    else
      socket
    end
  end

  # Every spinner on the screen stops when a read fails. `loading` is the usual
  # one, `narrative_loading` and its like are the rest: a screen that keeps
  # spinning while it is telling the operator the read failed is two answers at
  # once, and the spinner is the wrong one.
  defp stop_spinners(socket) do
    socket.assigns
    |> Map.keys()
    |> Enum.filter(&spinner?/1)
    |> Enum.reduce(socket, fn key, acc -> assign(acc, key, false) end)
  end

  defp spinner?(:loading), do: true
  defp spinner?(key), do: key |> Atom.to_string() |> String.ends_with?("_loading")

  @doc """
  Clear the failed read, when the attempt is of the read that failed.

  A retry of the question that went unanswered is news and the screen may say so.
  A different question starting is not news about this one, so the failure stands
  until the read it belongs to is asked again.
  """
  @spec started(map(), atom() | nil) :: map()
  def started(socket, tag) do
    if socket.assigns[:read_failed_tag] == tag do
      socket |> assign(:read_error, nil) |> assign(:read_failed_tag, nil)
    else
      socket
    end
  end

  @doc """
  What to tell the operator about a failed read.

  No blaming and no guessing: this is the dashboard saying what it knows. The
  first two sentences are the ones the habits screens already used, so that every
  screen answers a dead bot the same way.
  """
  @spec message(term()) :: String.t()
  def message(:no_broker), do: "the bot is not reachable right now"
  def message(:timeout), do: "the bot did not answer in time"
  def message(:broker_exit), do: "the connection to the message broker dropped"
  def message(:bad_reply), do: "the bot answered something this screen could not read"
  def message(:unexpected_reply), do: "the bot answered, but not with what this screen asked for"
  def message(:bad_payload), do: "this screen could not put its question together"
  def message(reason) when is_atom(reason) and not is_nil(reason), do: to_string(reason)
  def message(_reason), do: "the request failed"
end
