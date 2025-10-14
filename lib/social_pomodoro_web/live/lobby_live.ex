defmodule SocialPomodoroWeb.LobbyLive do
  use SocialPomodoroWeb, :live_view
  require Logger
  alias SocialPomodoroWeb.Icons
  alias SocialPomodoro.Utils

  @impl true
  def mount(params, session, socket) do
    user_id = session["user_id"]

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "rooms")
      Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "user:#{user_id}")
    end

    username = SocialPomodoro.UserRegistry.get_username(user_id) || "Unknown User"
    rooms = sort_rooms(SocialPomodoro.RoomRegistry.list_rooms(user_id), user_id)

    # Check if user is already in a room
    my_room_name =
      case SocialPomodoro.RoomRegistry.find_user_room(user_id) do
        {:ok, name} -> name
        {:error, :not_found} -> nil
      end

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:username, username)
      |> assign(:rooms, rooms)
      |> assign(:duration_minutes, 25)
      |> assign(:creating, false)
      |> assign(:my_room_name, my_room_name)

    # Handle direct room link (/at/:room_name) - only during connected mount
    socket =
      case {params, connected?(socket)} do
        {%{"room_name" => room_name}, true} when is_binary(room_name) ->
          handle_direct_room_join(socket, room_name, user_id)

        _ ->
          socket
      end

    {:ok, socket}
  end

  defp handle_direct_room_join(socket, room_name, user_id) do
    display_name = String.replace(room_name, "-", " ")

    # Check room status first to determine navigation path
    case SocialPomodoro.RoomRegistry.get_room(room_name) do
      {:ok, pid} ->
        room_state = SocialPomodoro.Room.get_state(pid)

        case room_state.status do
          :autostart ->
            # Room is waiting, join without setting my_room_name to avoid terminate callback
            case SocialPomodoro.Room.join(room_name, user_id) do
              :ok ->
                socket
                |> put_flash(:info, "Joined #{display_name}")
                |> push_navigate(to: ~p"/")

              {:error, reason} ->
                Logger.error("Failed to join room #{room_name}: #{inspect(reason)}")

                socket
                |> put_flash(:error, "Could not join room")
                |> push_navigate(to: ~p"/")
            end

          _ ->
            # Room is active or in break, use helper to set my_room_name
            case join_room_and_update_state(socket, room_name, user_id) do
              {:ok, socket} ->
                socket
                |> put_flash(:info, "Joined #{display_name}")
                |> push_navigate(to: ~p"/room/#{room_name}")

              {:error, socket} ->
                socket
                |> put_flash(:error, "Could not join room")
                |> push_navigate(to: ~p"/")
            end
        end

      {:error, _} ->
        socket
        |> put_flash(:error, "Room not found")
        |> push_navigate(to: ~p"/")
    end
  end

  defp join_room_and_update_state(socket, name, user_id) do
    case SocialPomodoro.Room.join(name, user_id) do
      :ok ->
        Logger.info("User #{user_id} joined room #{name}")

        socket =
          socket
          |> assign(:my_room_name, name)

        {:ok, socket}

      {:error, reason} ->
        Logger.error("User #{user_id} failed to join room #{name}: #{inspect(reason)}")
        {:error, socket}
    end
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
    {:ok, name} =
      SocialPomodoro.RoomRegistry.create_room(
        socket.assigns.user_id,
        socket.assigns.duration_minutes
      )

    socket = assign(socket, :my_room_name, name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_my_room", %{"room-name" => name}, socket) do
    SocialPomodoro.Room.start_session(name)
    {:noreply, push_navigate(socket, to: ~p"/room/#{name}")}
  end

  @impl true
  def handle_event("join_room", %{"room-name" => name}, socket) do
    case join_room_and_update_state(socket, name, socket.assigns.user_id) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, "Could not join room")}
    end
  end

  @impl true
  def handle_event("rejoin_room", %{"room-name" => name}, socket) do
    case join_room_and_update_state(socket, name, socket.assigns.user_id) do
      {:ok, socket} ->
        {:noreply, push_navigate(socket, to: ~p"/room/#{name}")}

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, "Could not rejoin room")}
    end
  end

  @impl true
  def handle_event("leave_room", _params, socket) do
    if socket.assigns.my_room_name do
      name = socket.assigns.my_room_name
      SocialPomodoro.Room.leave(name, socket.assigns.user_id)

      socket =
        socket
        |> assign(:my_room_name, nil)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("link_copied", _params, socket) do
    {:noreply, put_flash(socket, :info, "Room link copied!")}
  end

  @impl true
  def handle_info({:room_update, _room_state}, socket) do
    rooms =
      sort_rooms(
        SocialPomodoro.RoomRegistry.list_rooms(socket.assigns.user_id),
        socket.assigns.user_id
      )

    {:noreply, assign(socket, :rooms, rooms)}
  end

  @impl true
  def handle_info({:room_removed, name}, socket) do
    # If we were in this room, reset my_room_name
    socket =
      if socket.assigns.my_room_name == name do
        assign(socket, :my_room_name, nil)
      else
        socket
      end

    # Update rooms list
    rooms =
      sort_rooms(
        SocialPomodoro.RoomRegistry.list_rooms(socket.assigns.user_id),
        socket.assigns.user_id
      )

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
  def handle_info({:session_started, name}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/room/#{name}")}
  end

  defp sort_rooms(rooms, user_id) do
    Enum.sort_by(rooms, fn room ->
      # Sort by:
      # 1. User-created rooms first (creator == user_id)
      # 2. Then open rooms (status == :autostart)
      # 3. Then in-progress rooms (status == :active or :break)
      cond do
        room.creator == user_id -> {0, room.created_at}
        room.status == :autostart -> {1, room.created_at}
        true -> {2, room.created_at}
      end
    end)
  end

  defp min_timer_minutes do
    SocialPomodoro.Config.min_timer_minutes()
  end

  @impl true
  def terminate(_reason, socket) do
    # Leave room when LiveView process terminates (e.g., navigation away)
    # But only if the room is still in autostart status (haven't started session yet)
    if socket.assigns[:my_room_name] do
      case SocialPomodoro.RoomRegistry.get_room(socket.assigns.my_room_name) do
        {:ok, pid} ->
          room_state = SocialPomodoro.Room.get_state(pid)

          if room_state.status == :autostart do
            SocialPomodoro.Room.leave(socket.assigns.my_room_name, socket.assigns.user_id)
          end

        {:error, _} ->
          # Room doesn't exist anymore, nothing to do
          :ok
      end
    end

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    <div class="navbar bg-base-300 text-neutral-content">
      <div class="flex-1">
        <a href="/" class="btn btn-ghost text-xl">focus with strangers</a>
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

    <div class="min-h-screen bg-base-100 p-4 md:p-8">
      <div class="max-w-6xl mx-auto">
        <div class="grid grid-cols-1 lg:grid-cols-[1fr_auto] gap-8 mb-8">
          <!-- Left Column: Explanation -->
          <div class="card bg-base-200">
            <div class="card-body">
              <h1 class="card-title text-4xl mb-4">Fancy a Pomodoro?</h1>
              <div class="space-y-4 text-lg">
                <p class="leading-relaxed">Focus with strangers. Or friends.</p>

                <p class="leading-relaxed">
                  Create a room, set your timer, and get things done together.
                </p>
                <div>
                  <div class="badge badge-primary badge-dash badge-md lg:badge-lg p-4">No webcam</div>
                  <div class="badge badge-secondary badge-dash badge-md lg:badge-lg p-4">No chat</div>
                  <div class="badge badge-accent badge-dash badge-md lg:badge-lg p-4">Just work</div>
                </div>
              </div>
            </div>
          </div>
          <!-- Right Column: Username & Create Room -->
          <div class="space-y-8">
            <.user_card
              user_id={@user_id}
              username={@username}
              my_room_name={@my_room_name}
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
                    No one is here yet 🥺 <br /> That's okay! You can focus solo!
                  </p>
                </div>
              <% else %>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  <%= for room <- @rooms do %>
                    <.room_card
                      room={room}
                      user_id={@user_id}
                      my_room_name={@my_room_name}
                    />
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Attribution Footer -->
    <div class="text-center py-4 text-xs opacity-50">
      Emoji graphics by <a href="https://openmoji.org" target="_blank" class="link">OpenMoji</a>
      (CC BY-SA 4.0)
    </div>

    <.feedback_modal id="feedback-modal" username={@username}>
      <:trigger></:trigger>
    </.feedback_modal>
    """
  end

  defp can_rejoin?(room, user_id) do
    # User can rejoin if they're a session participant but not currently in the room
    is_session_participant = Enum.member?(room.session_participants, user_id)
    is_currently_in_room = Enum.any?(room.participants, &(&1.user_id == user_id))

    is_session_participant and not is_currently_in_room
  end

  attr :room, :map, required: true
  attr :user_id, :string, required: true
  attr :my_room_name, :string, default: nil

  defp room_card(assigns) do
    ~H"""
    <div class={"card bg-base-100
    bg-[repeating-radial-gradient(circle_at_center,rgba(255,255,255,0.05)_0,rgba(255,255,255,0.05)_2px,transparent_1px,transparent_20px)]
    bg-[size:20px_20px]
    " <>
      if @room.name == @my_room_name, do: "border-2 border-primary", else: ""}>
      <div class="card-body p-4 gap-3 flex flex-col justify-between min-h-48">
        <div>
          <div class="flex items-center justify-between gap-2">
            <h3 class="card-title font-semibold">{String.replace(@room.name, "-", " ")}</h3>
            <%= if @room.creator == @user_id or @room.name == @my_room_name do %>
              <button
                id={"share-btn-#{@room.name}"}
                phx-hook="CopyToClipboard"
                data-room-name={@room.name}
                class="btn btn-ghost btn-xs btn-square"
                title="Share room"
              >
                <Icons.share class="w-4 h-4 fill-current" />
              </button>
            <% end %>
            <%!-- Show spectator badge for in-progress rooms --%>
            <%= if @room.status in [:active, :break] && @room.spectators_count > 0 do %>
              <div
                class="tooltip tooltip-left"
                data-tip={Utils.count_with_word(@room.spectators_count, "spectator")}
              >
                <div class="badge badge-ghost gap-1">
                  <Icons.ghost class="w-3 h-3 fill-current" />
                  <span class="text-xs">{@room.spectators_count}</span>
                </div>
              </div>
            <% end %>
          </div>
          <div class="text-sm opacity-70">
            {Utils.count_with_word(length(@room.participants), "person", "people")} waiting · {@room.duration_minutes} min
          </div>
        </div>
        
    <!-- Participant Avatars -->
        <%= if length(@room.participants) > 0 do %>
          <div class="flex items-center justify-center min-h-16">
            <div class="avatar-group -space-x-6">
              <%= for participant <- @room.participants do %>
                <.avatar
                  user_id={participant.user_id}
                  username={participant.username}
                  size="w-10"
                />
              <% end %>
            </div>
          </div>
        <% end %>
        
    <!-- Action Button -->
        <div class="flex items-center justify-between gap-4 w-full">
          <!-- Status -->
          <div class="flex gap-2 items-center">
            <%= if @room.status == :autostart do %>
              <div class="badge badge-soft badge-warning gap-2 text-xs h-auto py-2">
                <div class="status status-warning animate-pulse flex-shrink-0"></div>
                <div class="flex flex-col sm:flex-row items-start sm:items-center gap-0 sm:gap-1 leading-tight">
                  <span class="text-xs">Starting</span>
                  <span
                    phx-hook="AutostartTimer"
                    id={"autostart-timer-#{@room.name}"}
                    data-seconds-remaining={@room.seconds_remaining}
                    class="font-mono font-semibold"
                  >
                    {format_time_remaining(@room.seconds_remaining)}
                  </span>
                </div>
              </div>
            <% else %>
              <div class="badge badge-soft badge-neutral gap-2 h-auto py-2">
                <svg class="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z"
                    clip-rule="evenodd"
                  />
                </svg>
                <span class="text-xs">In Progress</span>
              </div>
            <% end %>
          </div>
          
    <!-- Actions -->
          <div class="card-actions flex-shrink-0">
            <%= if @room.status == :autostart do %>
              <%= if @room.name == @my_room_name do %>
                <button
                  phx-click="leave_room"
                  class="btn btn-error btn-outline btn-sm"
                >
                  Leave
                </button>
                <%= if @room.creator == @user_id do %>
                  <button
                    phx-click="start_my_room"
                    phx-value-room-name={@room.name}
                    phx-hook="RequestWakeLock"
                    id={"start-room-btn-#{@room.name}"}
                    class="btn btn-primary btn-sm"
                  >
                    Start Now
                  </button>
                <% end %>
              <% else %>
                <button
                  phx-click="join_room"
                  phx-value-room-name={@room.name}
                  phx-hook="RequestWakeLock"
                  id={"join-room-btn-#{@room.name}"}
                  class="btn btn-primary btn-outline btn-sm"
                >
                  Join
                </button>
              <% end %>
            <% else %>
              <%= if can_rejoin?(@room, @user_id) do %>
                <button
                  phx-click="rejoin_room"
                  phx-value-room-name={@room.name}
                  class="btn btn-primary btn-outline btn-sm"
                >
                  Rejoin
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :user_id, :string, required: true
  attr :username, :string, required: true
  attr :my_room_name, :string, default: nil
  attr :duration_minutes, :integer, required: true

  defp user_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        
    <!-- Username Editor -->
        <div class="pb-4 border-b border-base-300">
          <!-- Avatar + username -->
          <div class="flex gap-2">
            <.participant_avatar
              user_id={@user_id}
              username={@username}
              current_user_id={@user_id}
              size="w-12"
            />
            <div>
              <span class="label label-text">Look, it's you!</span>

              <div class="flex items-center gap-2">
                <span id="username-display" class="font-bold text-base">{@username}</span>
                <button
                  type="button"
                  phx-click={JS.toggle(to: "#username-form") |> JS.focus(to: "#username-input")}
                  class="link link-hover text-xs text-base-content/70"
                >
                  <Icons.pencil class="w-4 h-4 inline fill-current" />
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

        <div class="flex flex-col mx-auto w-full lg:w-xs relative">
          <div class="relative z-0 bg-base-200/50 p-4 rounded-box">
            <!-- Duration Presets -->
            <%!-- TODO: make this client side --%>
            <div class="join w-full mb-2">
              <button
                phx-click="set_duration"
                phx-value-minutes="25"
                disabled={@my_room_name != nil}
                class={"join-item btn flex-1 !border-2 " <> if @duration_minutes == 25, do: "btn-primary btn-outline", else: "btn-neutral btn-outline"}
              >
                25 min
              </button>
              <button
                phx-click="set_duration"
                phx-value-minutes="50"
                disabled={@my_room_name != nil}
                class={"join-item btn flex-1 !border-2 " <> if @duration_minutes == 50, do: "btn-primary btn-outline", else: "btn-neutral btn-outline"}
              >
                50 min
              </button>
              <button
                phx-click="set_duration"
                phx-value-minutes="75"
                disabled={@my_room_name != nil}
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
                  min={min_timer_minutes()}
                  max="180"
                  value={@duration_minutes}
                  name="minutes"
                  disabled={@my_room_name != nil}
                  class="range range-neutral"
                />
              </form>
              <div class="flex justify-between text-xs opacity-50 mt-1">
                <span>{min_timer_minutes()} min</span>
                <span>3 hours</span>
              </div>
              <label for="duration-slider" class="label w-full">
                <span class="label-text mx-auto">Duration: {@duration_minutes} minutes</span>
              </label>
            </div>

            <div class="card-actions">
              <button
                phx-click="create_room"
                phx-hook="RequestWakeLock"
                id="create-room-btn"
                disabled={@my_room_name != nil}
                class="btn btn-primary btn-block"
              >
                Let's go
              </button>
            </div>
          </div>

          <%= if @my_room_name do %>
            <div class="absolute inset-0 z-10 flex items-center justify-center p-4 rounded-box backdrop-blur-md bg-white/[0.01] shadow-xl pointer-events-none">
              <div role="alert" class="alert alert-success pointer-events-auto">
                <span>You're already in a room!</span>
              </div>
            </div>
          <% end %>
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

  attr :user_id, :string, required: true
  attr :username, :string, required: true
  attr :current_user_id, :string, required: true
  attr :size, :string, default: "w-16"

  defp participant_avatar(assigns) do
    ~H"""
    <.avatar
      user_id={@user_id}
      username={@username}
      size={@size}
      class={
        if @user_id == @current_user_id do
          "ring-primary ring-offset-base-100 rounded-full ring-2 ring-offset-2"
        else
          ""
        end
      }
    />
    """
  end
end
