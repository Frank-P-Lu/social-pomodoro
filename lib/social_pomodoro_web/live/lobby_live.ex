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
      |> assign(:rooms, rooms)
      |> assign(:duration_minutes, 25)
      |> assign(:creating, false)
      |> assign(:my_room_id, my_room_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("update_username", %{"username" => username}, socket) do
    user_id = socket.assigns.user_id
    SocialPomodoro.UserRegistry.set_username(user_id, username)

    socket =
      socket
      |> assign(:username, username)
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
      {:noreply, assign(socket, :username, username)}
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
    <div class="min-h-screen bg-base-100 p-8">
      <div class="max-w-7xl mx-auto">
        <!-- Feedback Button -->
        <div class="flex justify-end mb-4">
          <button
            phx-click={SocialPomodoroWeb.CoreComponents.show_modal("feedback-modal")}
            class="btn btn-secondary"
          >
            💬 Give Feedback
          </button>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
          <!-- Left Column: Explanation -->
          <div class="card bg-base-200">
            <div class="card-body">
              <h1 class="card-title text-3xl">Fancy a Pomodoro?</h1>
              <div class="space-y-3">
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
          </div>
          <!-- Right Column: Username & Create Room -->
          <div class="space-y-8">
            <!-- Username Editor -->
            <div class="mt-6 pt-6 border-t border-base-300">
              <div class="flex items-center gap-3 mb-3">
                <div class="avatar">
                  <div class="w-12 rounded-full">
                    <img
                      src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{@user_id}"}
                      alt={@username}
                    />
                  </div>
                </div>
                <div class="flex-1">
                  <label class="label">
                    <span class="label-text">Your username</span>
                  </label>
                  <div class="flex items-center gap-2">
                    <span id="username-display" class="font-bold">{@username}</span>
                    <button
                      type="button"
                      phx-click={JS.toggle(to: "#username-form") |> JS.focus(to: "#username-input")}
                      class="link link-hover text-xs"
                    >
                      change?
                    </button>
                  </div>
                  <form
                    id="username-form"
                    phx-submit="update_username"
                    phx-submit-end={JS.hide(to: "#username-form")}
                    class="mt-2 flex gap-2 hidden"
                  >
                    <input
                      type="text"
                      id="username-input"
                      value={@username}
                      name="username"
                      class="input input-primary flex-1"
                      placeholder="Enter username"
                    />
                    <button
                      type="submit"
                      class="btn btn-primary"
                    >
                      Update
                    </button>
                  </form>
                </div>
              </div>
            </div>
            
    <!-- Create Room Section -->
            <div class="card bg-base-200">
              <div class="card-body">
                <h2 class="card-title">Create a Room</h2>

                <%= if @my_room_id do %>
                  <div role="alert" class="alert alert-success">
                    <span>You're already in a room!</span>
                  </div>
                <% end %>
                
    <!-- Duration Presets -->
                <div class="join">
                  <button
                    phx-click="set_duration"
                    phx-value-minutes="25"
                    disabled={@my_room_id != nil}
                    class={"join-item btn " <> if @duration_minutes == 25, do: "btn-primary", else: ""}
                  >
                    25 min
                  </button>
                  <button
                    phx-click="set_duration"
                    phx-value-minutes="50"
                    disabled={@my_room_id != nil}
                    class={"join-item btn " <> if @duration_minutes == 50, do: "btn-primary", else: ""}
                  >
                    50 min
                  </button>
                  <button
                    phx-click="set_duration"
                    phx-value-minutes="75"
                    disabled={@my_room_id != nil}
                    class={"join-item btn " <> if @duration_minutes == 75, do: "btn-primary", else: ""}
                  >
                    75 min
                  </button>
                </div>
                
    <!-- Duration Slider -->
                <div>
                  <label class="label">
                    <span class="label-text">Duration: {@duration_minutes} minutes</span>
                  </label>
                  <form phx-change="set_duration">
                    <input
                      type="range"
                      min="5"
                      max="180"
                      value={@duration_minutes}
                      name="minutes"
                      disabled={@my_room_id != nil}
                      class="range range-primary"
                    />
                  </form>
                  <div class="flex justify-between text-xs opacity-50 mt-1">
                    <span>5 min</span>
                    <span>3 hours</span>
                  </div>
                </div>

                <div class="card-actions">
                  <button
                    phx-click="create_room"
                    disabled={@my_room_id != nil}
                    class="btn btn-primary btn-block"
                  >
                    Create Room
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Lobby</h2>

            <div class="space-y-4">
              <%= if Enum.empty?(@rooms) do %>
                <div class="text-center py-12">
                  <p class="text-lg">
                    No one is here yet 🥺. That's okay! You can focus with yourself!
                  </p>
                </div>
              <% else %>
                <%= for room <- @rooms do %>
                  <div class={"card bg-base-100 " <>
                    if room.room_id == @my_room_id, do: "border-2 border-primary", else: ""}>
                    <div class="card-body p-4">
                      <div class="flex items-center justify-between">
                        <div class="flex-1">
                          <!-- Participant Avatars -->
                          <div class="avatar-group -space-x-6 mb-2">
                            <%= for participant <- room.participants do %>
                              <div class="avatar">
                                <div class="w-10">
                                  <img
                                    src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
                                    alt={participant.username}
                                  />
                                </div>
                              </div>
                            <% end %>
                          </div>
                          
    <!-- Room Info -->
                          <div class="text-sm opacity-70">
                            {length(room.participants)} {if length(room.participants) == 1,
                              do: "person",
                              else: "people"} · {room.duration_minutes} min
                            <%= if room.status != :waiting do %>
                              · {format_time_remaining(room.seconds_remaining)} remaining
                            <% end %>
                          </div>
                        </div>
                        
    <!-- Action Button -->
                        <div class="card-actions">
                          <%= if room.status == :waiting do %>
                            <%= if room.room_id == @my_room_id do %>
                              <%= if room.creator == @user_id do %>
                                <button
                                  phx-click="start_my_room"
                                  phx-value-room-id={room.room_id}
                                  class="btn btn-primary"
                                >
                                  Start
                                </button>
                              <% else %>
                                <div class="text-sm opacity-50">
                                  Waiting for host...
                                </div>
                              <% end %>
                              <button
                                phx-click="leave_room"
                                class="btn btn-error btn-outline"
                              >
                                Leave
                              </button>
                            <% else %>
                              <button
                                phx-click="join_room"
                                phx-value-room-id={room.room_id}
                                class="btn btn-primary"
                              >
                                Join
                              </button>
                            <% end %>
                          <% else %>
                            <div class="badge badge-lg badge-neutral gap-2">
                              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                                <path
                                  fill-rule="evenodd"
                                  d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z"
                                  clip-rule="evenodd"
                                />
                              </svg>
                              In Progress
                            </div>
                          <% end %>
                        </div>
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
