defmodule SocialPomodoroWeb.LobbyLive do
  use SocialPomodoroWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "rooms")

      user_id = session["user_id"]
      Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "user:#{user_id}")
    end

    user_id = session["user_id"]
    username = SocialPomodoro.UserRegistry.get_username(user_id) || "Unknown User"
    rooms = SocialPomodoro.RoomRegistry.list_rooms()

    # Check if user is already in a room
    my_room_id =
      case SocialPomodoro.RoomRegistry.find_user_room(user_id) do
        {:ok, room_id} -> room_id
        {:error, :not_found} -> nil
      end

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:username, username)
      |> assign(:edit_username, username)
      |> assign(:editing_username, false)
      |> assign(:rooms, rooms)
      |> assign(:duration_minutes, 25)
      |> assign(:creating, false)
      |> assign(:my_room_id, my_room_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_username_edit", _params, socket) do
    {:noreply, assign(socket, :editing_username, !socket.assigns.editing_username)}
  end

  @impl true
  def handle_event("change_username", %{"username" => username}, socket) do
    {:noreply, assign(socket, :edit_username, username)}
  end

  @impl true
  def handle_event("update_username", %{"username" => username}, socket) do
    user_id = socket.assigns.user_id
    SocialPomodoro.UserRegistry.set_username(user_id, username)

    socket =
      socket
      |> assign(:username, username)
      |> assign(:edit_username, username)
      |> assign(:editing_username, false)
      |> put_flash(:info, "Username updated!")

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_duration", %{"minutes" => minutes}, socket) do
    duration = String.to_integer(minutes)
    {:noreply, assign(socket, :duration_minutes, duration)}
  end

  @impl true
  def handle_event("create_room", _params, socket) do
    {:ok, room_id} =
      SocialPomodoro.RoomRegistry.create_room(
        socket.assigns.user_id,
        socket.assigns.duration_minutes
      )

    socket = assign(socket, :my_room_id, room_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_my_room", %{"room-id" => room_id}, socket) do
    SocialPomodoro.Room.start_session(room_id)
    {:noreply, push_navigate(socket, to: ~p"/room/#{room_id}")}
  end

  @impl true
  def handle_event("join_room", %{"room-id" => room_id}, socket) do
    case SocialPomodoro.Room.join(room_id, socket.assigns.user_id) do
      :ok ->
        # Stay in lobby, just update state to show we're in the room
        {:noreply, assign(socket, :my_room_id, room_id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not join room")}
    end
  end

  @impl true
  def handle_event("leave_room", _params, socket) do
    if socket.assigns.my_room_id do
      SocialPomodoro.Room.leave(socket.assigns.my_room_id, socket.assigns.user_id)
      {:noreply, assign(socket, :my_room_id, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:room_update, _room_state}, socket) do
    rooms = SocialPomodoro.RoomRegistry.list_rooms()
    {:noreply, assign(socket, :rooms, rooms)}
  end

  @impl true
  def handle_info({:room_removed, room_id}, socket) do
    # If we were in this room, reset my_room_id
    socket =
      if socket.assigns.my_room_id == room_id do
        assign(socket, :my_room_id, nil)
      else
        socket
      end

    # Update rooms list
    rooms = SocialPomodoro.RoomRegistry.list_rooms()
    {:noreply, assign(socket, :rooms, rooms)}
  end

  @impl true
  def handle_info({:username_updated, user_id, username}, socket) do
    if socket.assigns.user_id == user_id do
      socket =
        socket
        |> assign(:username, username)
        |> assign(:edit_username, username)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:session_started, room_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/room/#{room_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 p-8">
      <div class="max-w-7xl mx-auto">
        <!-- Feedback Button -->
        <div class="flex justify-end mb-4">
          <button
            phx-click={SocialPomodoroWeb.CoreComponents.show_modal("feedback-modal")}
            class="px-4 py-2 bg-gray-800 text-gray-100 font-medium rounded-lg shadow-sm hover:shadow-md transition-all border border-gray-700 hover:border-emerald-400"
          >
            💬 Give Feedback
          </button>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
          <!-- Left Column: Explanation -->
          <div class="bg-gray-800 rounded-2xl shadow-sm p-8 border border-gray-700">
            <h1 class="text-3xl font-bold text-gray-100 mb-4">Fancy a Pomodoro?</h1>
            <div class="text-gray-300 space-y-3">
              <p>Focus with strangers around the world.</p>
              <strong>No webcam. No chat.</strong>

              <p>
                Join a room or create your own. Set a timer, and work alongside others in real-time.
              </p>

              <p>
                React with emojis to share your progress and energy.
              </p>
              <p>
                After each session, take a 5-minute break together.
              </p>
              <p>
                Keep going or return to the lobby when you're done.
              </p>
            </div>
          </div>
          <!-- Right Column: Username & Create Room -->
          <div class="space-y-8">
            <!-- Username Editor -->
            <div class="mt-6 pt-6 border-t border-gray-700">
              <div class="flex items-center gap-3 mb-3">
                <img
                  src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{@user_id}"}
                  alt={@username}
                  class="w-12 h-12 rounded-full bg-gray-700"
                />
                <div>
                  <label class="block text-sm font-medium text-gray-300">
                    Your username
                  </label>
                  <div class="flex items-center gap-2">
                    <span class="font-bold text-gray-100">{@username}</span>
                    <button
                      phx-click="toggle_username_edit"
                      class="text-xs text-gray-400 underline hover:text-gray-200 transition-colors"
                    >
                      change?
                    </button>
                  </div>
                </div>
              </div>
              <%= if @editing_username do %>
                <form phx-change="change_username" phx-submit="update_username" class="flex gap-2">
                  <input
                    type="text"
                    value={@edit_username}
                    name="username"
                    class="flex-1 px-4 py-2 border border-gray-600 bg-gray-700 text-gray-100 rounded-lg focus:ring-2 focus:ring-emerald-400 focus:border-transparent"
                    placeholder="Enter username"
                  />
                  <button
                    type="submit"
                    class="px-4 py-2 bg-emerald-400 text-gray-900 font-medium rounded-lg hover:bg-emerald-500 transition-colors"
                  >
                    Update
                  </button>
                </form>
              <% end %>
            </div>
            
    <!-- Create Room Section -->
            <div class="bg-gray-800 rounded-2xl shadow-sm p-8 border border-gray-700">
              <h2 class="text-2xl font-semibold text-gray-100 mb-6">Create a Room</h2>

              <%= if @my_room_id do %>
                <div class="mb-4 p-3 bg-emerald-900/30 border border-emerald-400/30 rounded-lg">
                  <p class="text-sm text-emerald-300">You're already in a room!</p>
                </div>
              <% end %>
              
    <!-- Duration Presets -->
              <div class="flex gap-3 mb-6">
                <button
                  phx-click="set_duration"
                  phx-value-minutes="25"
                  disabled={@my_room_id != nil}
                  class={"px-6 py-2 rounded-lg font-medium transition-colors " <>
                    (if @duration_minutes == 25, do: "bg-emerald-400 text-gray-900", else: "bg-gray-700 text-gray-100 hover:bg-gray-600") <>
                    (if @my_room_id, do: " opacity-50 cursor-not-allowed", else: "")}
                >
                  25 min
                </button>
                <button
                  phx-click="set_duration"
                  phx-value-minutes="50"
                  disabled={@my_room_id != nil}
                  class={"px-6 py-2 rounded-lg font-medium transition-colors " <>
                    (if @duration_minutes == 50, do: "bg-emerald-400 text-gray-900", else: "bg-gray-700 text-gray-100 hover:bg-gray-600") <>
                    (if @my_room_id, do: " opacity-50 cursor-not-allowed", else: "")}
                >
                  50 min
                </button>
                <button
                  phx-click="set_duration"
                  phx-value-minutes="75"
                  disabled={@my_room_id != nil}
                  class={"px-6 py-2 rounded-lg font-medium transition-colors " <>
                    (if @duration_minutes == 75, do: "bg-emerald-400 text-gray-900", else: "bg-gray-700 text-gray-100 hover:bg-gray-600") <>
                    (if @my_room_id, do: " opacity-50 cursor-not-allowed", else: "")}
                >
                  75 min
                </button>
              </div>
              
    <!-- Duration Slider -->
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-300 mb-2">
                  Duration: {@duration_minutes} minutes
                </label>
                <form phx-change="set_duration">
                  <input
                    type="range"
                    min="5"
                    max="180"
                    value={@duration_minutes}
                    name="minutes"
                    disabled={@my_room_id != nil}
                    class={"w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-emerald-400" <>
                      if @my_room_id, do: " opacity-50 cursor-not-allowed", else: ""}
                  />
                </form>
                <div class="flex justify-between text-xs text-gray-400 mt-1">
                  <span>5 min</span>
                  <span>3 hours</span>
                </div>
              </div>

              <button
                phx-click="create_room"
                disabled={@my_room_id != nil}
                class={"w-full font-semibold py-3 rounded-lg transition-colors " <>
                  if @my_room_id, do: "bg-gray-700 text-gray-500 cursor-not-allowed", else: "bg-emerald-400 text-gray-900 hover:bg-emerald-500"}
              >
                Create Room
              </button>
            </div>
          </div>
          <!-- This closes the Right Column -->
        </div>
        <!-- This closes the grid -->

        <!-- Full Width: Open Rooms -->
        <div class="bg-gray-800 rounded-2xl shadow-sm p-8 border border-gray-700">
          <h2 class="text-2xl font-semibold text-gray-100 mb-6">Open Rooms</h2>

          <div class="space-y-4">
            <%= if Enum.empty?(@rooms) do %>
              <div class="text-center py-12 text-gray-300">
                <p class="text-lg">No one is here yet 🥺. That's okay! You can focus with yourself!</p>
              </div>
            <% else %>
              <%= for room <- @rooms do %>
                <div class={"rounded-lg p-4 hover:border-emerald-400/50 transition-colors " <>
                  if room.room_id == @my_room_id, do: "border-2 border-emerald-400", else: "border border-gray-700 bg-gray-800/50"}>
                  <div class="flex items-center justify-between">
                    <div class="flex-1">
                      <!-- Participant Avatars -->
                      <div class="flex items-center gap-2 mb-2">
                        <%= for participant <- room.participants do %>
                          <img
                            src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
                            alt={participant.username}
                            class="w-10 h-10 rounded-full bg-gray-700"
                          />
                        <% end %>
                      </div>
                      
    <!-- Room Info -->
                      <div class="text-sm text-gray-400">
                        {length(room.participants)} {if length(room.participants) == 1,
                          do: "person",
                          else: "people"} · {room.duration_minutes} min
                        <%= if room.status != :waiting do %>
                          · {format_time_remaining(room.seconds_remaining)} remaining
                        <% end %>
                      </div>
                    </div>
                    
    <!-- Action Button -->
                    <div class="ml-4 flex gap-2">
                      <%= if room.status == :waiting do %>
                        <%= if room.room_id == @my_room_id do %>
                          <%= if room.creator == @user_id do %>
                            <button
                              phx-click="start_my_room"
                              phx-value-room-id={room.room_id}
                              class="px-6 py-2 bg-emerald-500 text-gray-900 font-medium rounded-lg hover:bg-emerald-400 transition-colors"
                            >
                              Start
                            </button>
                          <% else %>
                            <div class="text-sm text-gray-500">
                              Waiting for host...
                            </div>
                          <% end %>
                          <button
                            phx-click="leave_room"
                            class="px-4 py-2 bg-rose-900/30 text-rose-300 font-medium rounded-lg hover:bg-rose-900/50 transition-colors border border-rose-700"
                          >
                            Leave
                          </button>
                        <% else %>
                          <button
                            phx-click="join_room"
                            phx-value-room-id={room.room_id}
                            class="px-6 py-2 bg-emerald-400 text-gray-900 font-medium rounded-lg hover:bg-emerald-500 transition-colors"
                          >
                            Join
                          </button>
                        <% end %>
                      <% else %>
                        <div class="flex items-center gap-2 text-gray-500">
                          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                            <path
                              fill-rule="evenodd"
                              d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z"
                              clip-rule="evenodd"
                            />
                          </svg>
                          <span class="text-sm font-medium">In Progress</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <.feedback_modal id="feedback-modal" username={@username}>
      <:trigger></:trigger>
    </.feedback_modal>
    """
  end

  defp format_time_remaining(nil), do: "0:00"

  defp format_time_remaining(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end
end
