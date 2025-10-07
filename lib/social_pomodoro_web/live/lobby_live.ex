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
    <div class="navbar bg-base-300 text-neutral-content">
      <div class="flex-1">
        <a href="/" class="btn btn-ghost text-xl">Focus with Strangers</a>
      </div>
      <div class="flex-none">
        <button
          phx-click={SocialPomodoroWeb.CoreComponents.show_modal("feedback-modal")}
          class="btn btn-secondary btn-dash"
        >
          Give Feedback
        </button>
      </div>
    </div>

    <div class="min-h-screen bg-base-100 p-8">
      <div class="max-w-6xl mx-auto">
        <div class="grid grid-cols-1 lg:grid-cols-[1fr_auto] gap-8 mb-8">
          <!-- Left Column: Explanation -->
          <div class="card bg-base-200">
            <div class="card-body">
              <h1 class="card-title text-4xl mb-4">Fancy a Pomodoro?</h1>
              <div class="space-y-4 text-lg">
                <p class="leading-relaxed">Focus with strangers. Or friends.</p>
                <div class="badge badge-primary badge-lg p-4">No webcam. No chat. Just work.</div>

                <p class="leading-relaxed">
                  Create a room, set your timer, and get things done together.
                </p>
              </div>
            </div>
          </div>
          <!-- Right Column: Username & Create Room -->
          <div class="space-y-8">
            <.user_card
              user_id={@user_id}
              username={@username}
              my_room_id={@my_room_id}
              duration_minutes={@duration_minutes}
            />
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
                  <.room_card room={room} user_id={@user_id} my_room_id={@my_room_id} />
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

  defp room_card(assigns) do
    ~H"""
    <div class={"card bg-base-100 " <>
      if @room.room_id == @my_room_id, do: "border-2 border-primary", else: ""}>
      <div class="card-body p-4 gap-0">
        <h3 class="card-title font-semibold">ROOM_NAME</h3>
        <div class="text-sm opacity-70">
          {length(@room.participants)} {if length(@room.participants) == 1,
            do: "person",
            else: "people"} waiting · {@room.duration_minutes} min
          <%= if @room.status != :waiting do %>
            · {format_time_remaining(@room.seconds_remaining)} remaining
          <% end %>
        </div>
        
    <!-- Participant Avatars -->
        <div class="flex items-center justify-center my-2">
          <div class="avatar-group -space-x-6 mb-2">
            <%= for participant <- @room.participants do %>
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
        </div>
        
    <!-- Action Button -->
        <div class="flex items-center justify-between gap-4">
          <!-- Status -->
          <div>
            <%= if @room.status == :waiting do %>
              <%= if @room.room_id == @my_room_id do %>
                <%= if @room.creator == @user_id do %>
                  <div class="text-sm opacity-70">Ready to start</div>
                <% else %>
                  <div class="text-sm opacity-50">
                    <div class="status status-primary animate-bounce"></div>
                    Waiting for host...
                  </div>
                <% end %>
              <% else %>
                <div class="text-sm opacity-70">Waiting</div>
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
          
    <!-- Actions -->
          <div class="card-actions">
            <%= if @room.status == :waiting do %>
              <%= if @room.room_id == @my_room_id do %>
                <%= if @room.creator == @user_id do %>
                  <button
                    phx-click="start_my_room"
                    phx-value-room-id={@room.room_id}
                    class="btn btn-primary btn-sm"
                  >
                    Start
                  </button>
                <% end %>
                <button
                  phx-click="leave_room"
                  class="btn btn-error btn-outline btn-sm"
                >
                  Leave
                </button>
              <% else %>
                <button
                  phx-click="join_room"
                  phx-value-room-id={@room.room_id}
                  class="btn btn-primary btn-sm"
                >
                  Join
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp user_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <!-- Username Editor -->
        <div class="pb-4 border-b border-base-300">
          <!-- Avatar + username -->
          <div class="flex gap-2">
            <div class="avatar">
              <div class="w-12 rounded-full">
                <img
                  src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{@user_id}"}
                  alt={@username}
                />
              </div>
            </div>
            <div>
              <span class="label label-text">Look, it's you!</span>

              <div class="flex items-center gap-4">
                <span id="username-display" class="font-bold text-base">{@username}</span>
                <button
                  type="button"
                  phx-click={JS.toggle(to: "#username-form") |> JS.focus(to: "#username-input")}
                  class="link link-hover text-xs text-base-content/70"
                >
                  change?
                </button>
              </div>
            </div>
          </div>
          <form
            id="username-form"
            phx-submit="update_username"
            class="mt-4 hidden "
          >
            <div class="flex flex-col gap-2">
              <input
                type="text"
                id="username-input"
                value={@username}
                name="username"
                autocomplete="username"
                class="input input-primary"
                placeholder="Enter username"
              />
              <button
                type="submit"
                phx-click={JS.hide(to: "#username-form")}
                class="btn btn-primary btn-outline "
              >
                Update
              </button>
            </div>
          </form>
        </div>

        <h2 class="card-title mt-4 mb-2">Set your timer</h2>

        <div class="flex flex-col mx-auto w-full lg:w-xs">
          <%= if @my_room_id do %>
            <div role="alert" class="alert alert-success mb-4">
              <span>You're already in a room!</span>
            </div>
          <% end %>
          
    <!-- Duration Presets -->
          <%!-- TODO: make this client side --%>
          <div class="join w-full mb-2">
            <button
              phx-click="set_duration"
              phx-value-minutes="25"
              disabled={@my_room_id != nil}
              class={"join-item btn flex-1 !border-2 " <> if @duration_minutes == 25, do: "btn-primary btn-outline", else: "btn-neutral btn-outline"}
            >
              25 min
            </button>
            <button
              phx-click="set_duration"
              phx-value-minutes="50"
              disabled={@my_room_id != nil}
              class={"join-item btn flex-1 !border-2 " <> if @duration_minutes == 50, do: "btn-primary btn-outline", else: "btn-neutral btn-outline"}
            >
              50 min
            </button>
            <button
              phx-click="set_duration"
              phx-value-minutes="75"
              disabled={@my_room_id != nil}
              class={"join-item btn flex-1 !border-2 " <> if @duration_minutes == 75, do: "btn-primary btn-outline", else: "btn-neutral btn-outline"}
            >
              75 min
            </button>
          </div>
          
    <!-- Duration Slider -->
          <div class="mb-4">
            <form phx-change="set_duration">
              <input
                type="range"
                id="duration-slider"
                min="5"
                max="180"
                value={@duration_minutes}
                name="minutes"
                disabled={@my_room_id != nil}
                class="range range-neutral"
              />
            </form>
            <div class="flex justify-between text-xs opacity-50 mt-1">
              <span>5 min</span>
              <span>3 hours</span>
            </div>
            <label for="duration-slider" class="label w-full">
              <span class="label-text mx-auto">Duration: {@duration_minutes} minutes</span>
            </label>
          </div>

          <div class="card-actions">
            <button
              phx-click="create_room"
              disabled={@my_room_id != nil}
              class="btn btn-primary btn-block"
            >
              Let's go
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_time_remaining(nil), do: "0:00"

  defp format_time_remaining(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end
end
