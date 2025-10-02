defmodule SocialPomodoroWeb.SessionLive do
  use SocialPomodoroWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    room_id = params["room_id"]
    username = params["username"] || "User#{:rand.uniform(999)}"

    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, _pid} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "room:#{room_id}")
        end

        # Get initial room state
        {:ok, pid} = SocialPomodoro.RoomRegistry.get_room(room_id)
        room_state = SocialPomodoro.Room.get_state(pid)

        socket =
          socket
          |> assign(:room_id, room_id)
          |> assign(:room_state, room_state)
          |> assign(:username, username)
          |> assign(:selected_emoji, nil)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("start_session", _params, socket) do
    SocialPomodoro.Room.start_session(socket.assigns.room_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_reaction", %{"emoji" => emoji}, socket) do
    SocialPomodoro.Room.add_reaction(
      socket.assigns.room_id,
      socket.assigns.username,
      emoji
    )
    {:noreply, socket}
  end

  @impl true
  def handle_event("go_again", _params, socket) do
    SocialPomodoro.Room.go_again(socket.assigns.room_id, socket.assigns.username)
    {:noreply, socket}
  end

  @impl true
  def handle_event("leave_room", _params, socket) do
    SocialPomodoro.Room.leave(socket.assigns.room_id, socket.assigns.username)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:room_state, room_state}, socket) do
    {:noreply, assign(socket, :room_state, room_state)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-50 to-purple-50 flex items-center justify-center p-8">
      <div class="max-w-4xl w-full">
        <%= if @room_state.status == :waiting do %>
          <.waiting_view room_state={@room_state} username={@username} />
        <% end %>

        <%= if @room_state.status == :active do %>
          <.active_session_view room_state={@room_state} />
        <% end %>

        <%= if @room_state.status == :break do %>
          <.break_view room_state={@room_state} username={@username} />
        <% end %>
      </div>
    </div>
    """
  end

  defp waiting_view(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-lg p-12 text-center">
      <h1 class="text-3xl font-bold text-gray-900 mb-8">Waiting to Start</h1>

      <!-- Participants -->
      <div class="flex justify-center gap-4 mb-8">
        <%= for participant <- @room_state.participants do %>
          <div class="text-center">
            <div class="w-16 h-16 rounded-full bg-gradient-to-br from-indigo-400 to-purple-400 flex items-center justify-center text-white font-bold text-xl mb-2">
              <%= String.first(participant.username) |> String.upcase() %>
            </div>
            <p class="text-sm text-gray-600"><%= participant.username %></p>
          </div>
        <% end %>
      </div>

      <p class="text-lg text-gray-600 mb-8">
        <%= length(@room_state.participants) %> <%= if length(@room_state.participants) == 1, do: "person", else: "people" %> in room
        · <%= @room_state.duration_minutes %> minute session
      </p>

      <%= if @room_state.creator == @username do %>
        <button
          phx-click="start_session"
          class="px-8 py-4 bg-indigo-600 text-white font-semibold text-lg rounded-lg hover:bg-indigo-700 transition-colors"
        >
          Start Session
        </button>
      <% else %>
        <p class="text-gray-500">Waiting for <%= @room_state.creator %> to start...</p>
      <% end %>

      <button
        phx-click="leave_room"
        class="mt-4 text-gray-500 hover:text-gray-700 underline"
      >
        Leave Room
      </button>
    </div>
    """
  end

  defp active_session_view(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-lg p-12">
      <!-- Timer Display -->
      <div class="text-center mb-12">
        <div class="text-8xl font-bold text-indigo-600 mb-4">
          <%= format_time(@room_state.seconds_remaining) %>
        </div>
        <p class="text-xl text-gray-600">Focus time remaining</p>
      </div>

      <!-- Participants -->
      <div class="flex justify-center gap-4 mb-8">
        <%= for participant <- @room_state.participants do %>
          <div class="w-12 h-12 rounded-full bg-gradient-to-br from-indigo-400 to-purple-400 flex items-center justify-center text-white font-semibold">
            <%= String.first(participant.username) |> String.upcase() %>
          </div>
        <% end %>
      </div>

      <!-- Reaction Buttons -->
      <div class="flex justify-center gap-4 mb-8">
        <button
          phx-click="send_reaction"
          phx-value-emoji="🔥"
          class="px-6 py-3 text-4xl bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
        >
          🔥
        </button>
        <button
          phx-click="send_reaction"
          phx-value-emoji="💪"
          class="px-6 py-3 text-4xl bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
        >
          💪
        </button>
        <button
          phx-click="send_reaction"
          phx-value-emoji="⚡"
          class="px-6 py-3 text-4xl bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
        >
          ⚡
        </button>
        <button
          phx-click="send_reaction"
          phx-value-emoji="🎯"
          class="px-6 py-3 text-4xl bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
        >
          🎯
        </button>
      </div>

      <!-- Recent Reactions -->
      <%= if !Enum.empty?(@room_state.reactions) do %>
        <div class="bg-gray-50 rounded-lg p-4 max-h-32 overflow-y-auto">
          <div class="flex flex-wrap gap-2">
            <%= for reaction <- Enum.take(@room_state.reactions, 20) do %>
              <div class="inline-flex items-center gap-1 bg-white px-3 py-1 rounded-full text-sm">
                <span><%= reaction.emoji %></span>
                <span class="text-gray-600"><%= reaction.username %></span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="text-center mt-6">
        <button
          phx-click="leave_room"
          class="text-gray-500 hover:text-gray-700 underline text-sm"
        >
          Leave Session
        </button>
      </div>
    </div>
    """
  end

  defp break_view(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-lg p-12 text-center">
      <div class="text-6xl mb-6">🎉</div>
      <h1 class="text-4xl font-bold text-gray-900 mb-4">Great Work!</h1>
      <p class="text-xl text-gray-600 mb-8">
        You just focused for <%= @room_state.duration_minutes %> minutes with <%= length(@room_state.participants) %> <%= if length(@room_state.participants) == 1, do: "person", else: "people" %>!
      </p>

      <div class="text-5xl font-bold text-indigo-600 mb-2">
        <%= format_time(@room_state.seconds_remaining) %>
      </div>
      <p class="text-lg text-gray-500 mb-12">Break time remaining</p>

      <!-- Participants with ready status -->
      <div class="flex justify-center gap-4 mb-8">
        <%= for participant <- @room_state.participants do %>
          <div class="text-center">
            <div class={"w-16 h-16 rounded-full flex items-center justify-center text-white font-semibold text-xl mb-2 " <>
              if participant.ready_for_next, do: "bg-gradient-to-br from-green-400 to-emerald-400", else: "bg-gradient-to-br from-gray-300 to-gray-400"}>
              <%= String.first(participant.username) |> String.upcase() %>
            </div>
            <%= if participant.ready_for_next do %>
              <p class="text-xs text-green-600 font-semibold">Ready!</p>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="flex gap-4 justify-center">
        <button
          phx-click="go_again"
          class="px-8 py-4 bg-indigo-600 text-white font-semibold text-lg rounded-lg hover:bg-indigo-700 transition-colors"
        >
          Go Again Together
        </button>
        <button
          phx-click="leave_room"
          class="px-8 py-4 bg-gray-200 text-gray-700 font-semibold text-lg rounded-lg hover:bg-gray-300 transition-colors"
        >
          Return to Lobby
        </button>
      </div>

      <%= if Enum.any?(@room_state.participants, & &1.ready_for_next) do %>
        <p class="text-sm text-gray-500 mt-6">
          Waiting for everyone to be ready...
        </p>
      <% end %>
    </div>
    """
  end

  defp format_time(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time(_), do: "0:00"
end
