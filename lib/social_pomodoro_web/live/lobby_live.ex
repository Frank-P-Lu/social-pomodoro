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

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:username, username)
      |> assign(:edit_username, username)
      |> assign(:rooms, rooms)
      |> assign(:duration_minutes, 25)
      |> assign(:creating, false)
      |> assign(:my_room_id, nil)

    {:ok, socket}
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
  def handle_event("start_my_room", _params, socket) do
    room_id = socket.assigns.my_room_id
    {:noreply, push_navigate(socket, to: ~p"/room/#{room_id}")}
  end

  @impl true
  def handle_event("join_room", %{"room-id" => room_id}, socket) do
    case SocialPomodoro.Room.join(room_id, socket.assigns.user_id) do
      :ok ->
        {:noreply, push_navigate(socket, to: ~p"/room/#{room_id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not join room")}
    end
  end

  @impl true
  def handle_info({:room_update, _room_state}, socket) do
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
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-50 to-purple-50 p-8">
      <div class="max-w-7xl mx-auto">
        <!-- Feedback Button -->
        <div class="flex justify-end mb-4">
          <button
            phx-click={SocialPomodoroWeb.CoreComponents.show_modal("feedback-modal")}
            class="px-4 py-2 bg-white text-gray-700 font-medium rounded-lg shadow-sm hover:shadow-md transition-all border border-gray-200 hover:border-gray-300"
          >
            💬 Give Feedback
          </button>
        </div>
        
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <!-- Left Column: About & Create -->
          <div class="space-y-8">
            <!-- About Section -->
            <div class="bg-white rounded-2xl shadow-sm p-8">
              <h1 class="text-3xl font-bold text-gray-900 mb-4">Social Pomodoro</h1>
              <div class="text-gray-600 space-y-3">
                <p>Focus with strangers around the world.</p>
                <p>
                  Join a room or create your own, set a timer, and work alongside others in real-time.
                </p>
                <p>React with emojis to share your progress and energy.</p>
                <p>After each session, take a 5-minute break together.</p>
                <p>Keep going or return to the lobby when you're done.</p>
              </div>
              
    <!-- Username Editor -->
              <div class="mt-6 pt-6 border-t border-gray-200">
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Your username: <span class="font-bold text-gray-900">{@username}</span>
                </label>
                <form phx-change="change_username" phx-submit="update_username" class="flex gap-2">
                  <input
                    type="text"
                    value={@edit_username}
                    name="username"
                    class="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
                    placeholder="Enter username"
                  />
                  <button
                    type="submit"
                    class="px-4 py-2 bg-indigo-600 text-white font-medium rounded-lg hover:bg-indigo-700 transition-colors"
                  >
                    Update
                  </button>
                </form>
              </div>
            </div>
            
    <!-- Create Room Section -->
            <div class="bg-white rounded-2xl shadow-sm p-8">
              <h2 class="text-2xl font-semibold text-gray-900 mb-6">Create a Room</h2>
              
    <!-- Duration Presets -->
              <div class="flex gap-3 mb-6">
                <button
                  phx-click="set_duration"
                  phx-value-minutes="25"
                  class={"px-6 py-2 rounded-lg font-medium transition-colors " <>
                    if @duration_minutes == 25, do: "bg-indigo-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}
                >
                  25 min
                </button>
                <button
                  phx-click="set_duration"
                  phx-value-minutes="50"
                  class={"px-6 py-2 rounded-lg font-medium transition-colors " <>
                    if @duration_minutes == 50, do: "bg-indigo-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}
                >
                  50 min
                </button>
                <button
                  phx-click="set_duration"
                  phx-value-minutes="75"
                  class={"px-6 py-2 rounded-lg font-medium transition-colors " <>
                    if @duration_minutes == 75, do: "bg-indigo-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}
                >
                  75 min
                </button>
              </div>

    <!-- Duration Slider -->
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Duration: <%= @duration_minutes %> minutes
                </label>
                <form phx-change="set_duration">
                  <input
                    type="range"
                    min="5"
                    max="180"
                    value={@duration_minutes}
                    name="minutes"
                    class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-indigo-600"
                  />
                </form>
                <div class="flex justify-between text-xs text-gray-500 mt-1">
                  <span>5 min</span>
                  <span>3 hours</span>
                </div>
              </div>

              <button
                phx-click="create_room"
                class="w-full bg-indigo-600 text-white font-semibold py-3 rounded-lg hover:bg-indigo-700 transition-colors"
              >
                Create Room
              </button>
            </div>
          </div>
          
    <!-- Right Column: Room List -->
          <div class="bg-white rounded-2xl shadow-sm p-8">
            <h2 class="text-2xl font-semibold text-gray-900 mb-6">Open Rooms</h2>

            <div class="space-y-4">
              <%= if Enum.empty?(@rooms) do %>
                <div class="text-center py-12 text-gray-500">
                  <p class="text-lg">No rooms available</p>
                  <p class="text-sm mt-2">Create one to get started!</p>
                </div>
              <% else %>
                <%= for room <- @rooms do %>
                  <div class={"rounded-lg p-4 hover:border-indigo-300 transition-colors " <>
                    if room.room_id == @my_room_id, do: "border-2 border-indigo-500", else: "border border-gray-200"}>
                    <div class="flex items-center justify-between">
                      <div class="flex-1">
                        <!-- Participant Avatars -->
                        <div class="flex items-center gap-2 mb-2">
                          <%= for participant <- room.participants do %>
                            <div class="w-10 h-10 rounded-full bg-gradient-to-br from-indigo-400 to-purple-400 flex items-center justify-center text-white font-semibold text-sm">
                              {String.first(participant.username) |> String.upcase()}
                            </div>
                          <% end %>
                        </div>
                        
    <!-- Room Info -->
                        <div class="text-sm text-gray-600">
                          {length(room.participants)} {if length(room.participants) == 1,
                            do: "person",
                            else: "people"} · {room.duration_minutes} min
                          <%= if room.status != :waiting do %>
                            · {format_time_remaining(room.seconds_remaining)} remaining
                          <% end %>
                        </div>
                      </div>
                      
    <!-- Action Button -->
                      <div class="ml-4">
                        <%= if room.status == :waiting do %>
                          <%= if room.room_id == @my_room_id do %>
                            <button
                              phx-click="start_my_room"
                              class="px-6 py-2 bg-green-600 text-white font-medium rounded-lg hover:bg-green-700 transition-colors"
                            >
                              Start
                            </button>
                          <% else %>
                            <button
                              phx-click="join_room"
                              phx-value-room-id={room.room_id}
                              class="px-6 py-2 bg-indigo-600 text-white font-medium rounded-lg hover:bg-indigo-700 transition-colors"
                            >
                              Join
                            </button>
                          <% end %>
                        <% else %>
                          <div class="flex items-center gap-2 text-gray-400">
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
    </div>
    
    <.feedback_modal id="feedback-modal">
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
