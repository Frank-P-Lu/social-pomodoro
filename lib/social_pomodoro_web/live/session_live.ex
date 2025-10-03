defmodule SocialPomodoroWeb.SessionLive do
  use SocialPomodoroWeb, :live_view

  @impl true
  def mount(params, session, socket) do
    room_id = params["room_id"]
    user_id = session["user_id"]
    username = SocialPomodoro.UserRegistry.get_username(user_id) || "Unknown User"

    case SocialPomodoro.RoomRegistry.get_room(room_id) do
      {:ok, _pid} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "room:#{room_id}")
          Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "user:#{user_id}")
        end

        # Get initial room state
        {:ok, pid} = SocialPomodoro.RoomRegistry.get_room(room_id)
        room_state = SocialPomodoro.Room.get_state(pid)

        # Check if user is already in the room, if not, try to join
        user_in_room = Enum.any?(room_state.participants, &(&1.user_id == user_id))

        if user_in_room do
          # User is already in the room, let them in
          socket =
            socket
            |> assign(:room_id, room_id)
            |> assign(:room_state, room_state)
            |> assign(:user_id, user_id)
            |> assign(:username, username)
            |> assign(:selected_emoji, nil)
            |> assign(:redirect_countdown, nil)

          {:ok, socket}
        else
          # User not in room, show redirect screen
          Process.send_after(self(), :countdown, 1000)

          socket =
            socket
            |> assign(:room_id, room_id)
            |> assign(:room_state, room_state)
            |> assign(:user_id, user_id)
            |> assign(:username, username)
            |> assign(:selected_emoji, nil)
            |> assign(:redirect_countdown, 5)

          {:ok, socket}
        end

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
      socket.assigns.user_id,
      emoji
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("go_again", _params, socket) do
    SocialPomodoro.Room.go_again(socket.assigns.room_id, socket.assigns.user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("leave_room", _params, socket) do
    SocialPomodoro.Room.leave(socket.assigns.room_id, socket.assigns.user_id)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:room_state, room_state}, socket) do
    {:noreply, assign(socket, :room_state, room_state)}
  end

  @impl true
  def handle_info({:username_updated, user_id, username}, socket) do
    if socket.assigns.user_id == user_id do
      {:noreply, assign(socket, :username, username)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:countdown, socket) do
    case socket.assigns.redirect_countdown do
      1 ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      n ->
        Process.send_after(self(), :countdown, 1000)
        {:noreply, assign(socket, :redirect_countdown, n - 1)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 flex items-center justify-center p-8">
      <div class="max-w-4xl w-full">
        <%= if @redirect_countdown do %>
          <.redirect_view countdown={@redirect_countdown} />
        <% else %>
          <%= if @room_state.status == :waiting do %>
            <.waiting_view room_state={@room_state} user_id={@user_id} />
          <% end %>

          <%= if @room_state.status == :active do %>
            <.active_session_view room_state={@room_state} />
          <% end %>

          <%= if @room_state.status == :break do %>
            <.break_view room_state={@room_state} user_id={@user_id} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp waiting_view(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-2xl shadow-lg p-12 text-center border border-gray-700">
      <h1 class="text-3xl font-bold text-gray-100 mb-8">Waiting to Start</h1>
      
    <!-- Participants -->
      <div class="flex justify-center gap-4 mb-8">
        <%= for participant <- @room_state.participants do %>
          <div class="text-center">
            <img
              src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
              alt={participant.username}
              class="w-16 h-16 rounded-full bg-gray-700 mb-2"
            />
            <p class="text-sm text-gray-300">{participant.username}</p>
          </div>
        <% end %>
      </div>

      <p class="text-lg text-gray-300 mb-8">
        {length(@room_state.participants)} {if length(@room_state.participants) == 1,
          do: "person",
          else: "people"} in room
        · {@room_state.duration_minutes} minute session
      </p>

      <%= if @room_state.creator == @user_id do %>
        <button
          phx-click="start_session"
          class="px-8 py-4 bg-emerald-400 text-gray-900 font-semibold text-lg rounded-lg hover:bg-emerald-500 transition-colors"
        >
          Start Session
        </button>
      <% else %>
        <p class="text-gray-400">Waiting for {@room_state.creator_username} to start...</p>
      <% end %>

      <button phx-click="leave_room" class="mt-4 text-gray-400 hover:text-gray-300 underline">
        Leave Room
      </button>
    </div>
    """
  end

  defp active_session_view(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-2xl shadow-lg p-12 border border-gray-700">
      <!-- Timer Display -->
      <div
        id="timer-display"
        class="text-5xl font-bold text-emerald-400 mb-2"
        phx-hook="Timer"
        data-seconds-remaining={@room_state.seconds_remaining}
      >
        {format_time(@room_state.seconds_remaining)}
      </div>
      <p class="text-xl text-gray-300">Focus time remaining</p>
      
    <!-- Participants -->
      <div class="flex justify-center gap-4 mb-8">
        <%= for participant <- @room_state.participants do %>
          <img
            src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
            alt={participant.username}
            class="w-12 h-12 rounded-full bg-gray-700"
          />
        <% end %>
      </div>
      <!-- Reaction Buttons -->
      <div class="flex justify-center gap-4 mb-8">
        <button
          phx-click="send_reaction"
          phx-value-emoji="🔥"
          class="px-6 py-3 text-4xl bg-gray-700 rounded-lg hover:bg-gray-600 transition-colors"
        >
          🔥
        </button>
        <button
          phx-click="send_reaction"
          phx-value-emoji="💪"
          class="px-6 py-3 text-4xl bg-gray-700 rounded-lg hover:bg-gray-600 transition-colors"
        >
          💪
        </button>
        <button
          phx-click="send_reaction"
          phx-value-emoji="⚡"
          class="px-6 py-3 text-4xl bg-gray-700 rounded-lg hover:bg-gray-600 transition-colors"
        >
          ⚡
        </button>
        <button
          phx-click="send_reaction"
          phx-value-emoji="🎯"
          class="px-6 py-3 text-4xl bg-gray-700 rounded-lg hover:bg-gray-600 transition-colors"
        >
          🎯
        </button>
      </div>
      
    <!-- Recent Reactions -->
      <%= if !Enum.empty?(@room_state.reactions) do %>
        <div class="bg-gray-700/50 rounded-lg p-4 max-h-32 overflow-y-auto">
          <div class="flex flex-wrap gap-2">
            <%= for reaction <- Enum.take(@room_state.reactions, 20) do %>
              <div class="inline-flex items-center gap-1 bg-gray-800 px-3 py-1 rounded-full text-sm">
                <span>{reaction.emoji}</span>
                <span class="text-gray-300">{reaction.username}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="text-center mt-6">
        <button phx-click="leave_room" class="text-gray-400 hover:text-gray-300 underline text-sm">
          Leave Session
        </button>
      </div>
    </div>
    """
  end

  defp break_view(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-2xl shadow-lg p-12 text-center border border-gray-700">
      <div class="text-6xl mb-6">🎉</div>
      <h1 class="text-4xl font-bold text-gray-100 mb-4">Great Work!</h1>
      <p class="text-xl text-gray-300 mb-8">
        You just focused for {@room_state.duration_minutes} minutes with {length(
          @room_state.participants
        )} {if length(@room_state.participants) == 1, do: "person", else: "people"}!
      </p>

      <div class="text-5xl font-bold text-emerald-400 mb-2">
        {format_time(@room_state.seconds_remaining)}
      </div>
      <p class="text-lg text-gray-400 mb-12">Break time remaining</p>
      
    <!-- Participants with ready status -->
      <div class="flex justify-center gap-4 mb-8">
        <%= for participant <- @room_state.participants do %>
          <div class="text-center">
            <div class="relative w-16 h-16 mb-2">
              <img
                src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
                alt={participant.username}
                class="w-16 h-16 rounded-full bg-gray-700"
              />
              <%= if participant.ready_for_next do %>
                <div class="absolute -top-1 -right-1 w-5 h-5 bg-emerald-500 rounded-full border-2 border-gray-800 flex items-center justify-center">
                  <span class="text-gray-900 text-xs">✓</span>
                </div>
              <% end %>
            </div>
            <%= if participant.ready_for_next do %>
              <p class="text-xs text-emerald-400 font-semibold">Ready!</p>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="flex gap-4 justify-center">
        <button
          phx-click="go_again"
          class="px-8 py-4 bg-emerald-400 text-gray-900 font-semibold text-lg rounded-lg hover:bg-emerald-500 transition-colors"
        >
          Go Again Together
        </button>
        <button
          phx-click="leave_room"
          class="px-8 py-4 bg-gray-700 text-gray-100 font-semibold text-lg rounded-lg hover:bg-gray-600 transition-colors"
        >
          Return to Lobby
        </button>
      </div>

      <%= if Enum.any?(@room_state.participants, & &1.ready_for_next) do %>
        <p class="text-sm text-gray-400 mt-6">
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

  defp redirect_view(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-2xl shadow-lg p-12 text-center border border-gray-700">
      <div class="text-6xl mb-6">👋</div>
      <h1 class="text-3xl font-bold text-gray-100 mb-4">Oops! You're not in this room</h1>
      <p class="text-xl text-gray-300 mb-8">
        This session is only for participants who joined from the lobby.
      </p>
      <p class="text-lg text-gray-400 mb-8">
        Heading back to the lobby in <span class="font-bold text-emerald-400">{@countdown}</span>
        {if @countdown == 1, do: "second", else: "seconds"}...
      </p>
      <a
        href="/"
        class="inline-block px-8 py-4 bg-emerald-400 text-gray-900 font-semibold text-lg rounded-lg hover:bg-emerald-500 transition-colors"
      >
        Go to Lobby Now
      </a>
    </div>
    """
  end
end
