defmodule SocialPomodoroWeb.LobbyLive do
  use SocialPomodoroWeb, :live_view
  require Logger
  alias SocialPomodoro.Utils
  alias SocialPomodoroWeb.Icons

  @impl true
  def mount(params, session, socket) do
    user_id = session["user_id"]
    username = SocialPomodoro.UserRegistry.get_username(user_id) || "Unknown User"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "rooms")
      Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "user:#{user_id}")
      Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "app:global")

      # Track this user's presence
      SocialPomodoroWeb.Presence.track(self(), "app:global", user_id, %{
        username: username
      })
    end

    active_user_count =
      if connected?(socket) do
        SocialPomodoroWeb.Presence.list("app:global") |> map_size()
      else
        0
      end

    rooms = sort_rooms(SocialPomodoro.RoomRegistry.list_rooms(user_id), user_id)

    # Check if user is already in a room
    my_room_name =
      case SocialPomodoro.RoomRegistry.find_user_room(user_id) do
        {:ok, name} -> name
        {:error, :not_found} -> nil
      end

    default_duration = SocialPomodoro.Config.default_pomodoro_duration()

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:username, username)
      |> assign(:rooms, rooms)
      |> assign(:creating, false)
      |> assign(:my_room_name, my_room_name)
      |> assign(:active_user_count, active_user_count)
      |> assign_timer_defaults(default_duration)

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
    SocialPomodoro.UserRegistry.register_or_update_user(user_id, username)

    {:noreply, assign(socket, :username, username)}
  end

  @impl true
  def handle_event("set_duration", %{"minutes" => minutes}, socket) do
    duration = String.to_integer(minutes)
    {:noreply, assign_timer_defaults(socket, duration)}
  end

  @impl true
  def handle_event("set_cycles", %{"cycles" => cycles}, socket) do
    num_cycles = String.to_integer(cycles)

    socket =
      socket
      |> assign(:num_cycles, num_cycles)
      |> assign(:break_options_disabled, num_cycles == 1)

    socket =
      if num_cycles == 1 do
        assign(
          socket,
          :break_duration_minutes,
          SocialPomodoro.Config.single_cycle_break_duration()
        )
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "set_break_duration",
        _params,
        %{assigns: %{break_options_disabled: true}} = socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_break_duration", %{"minutes" => minutes}, socket) do
    break_duration = String.to_integer(minutes)
    {:noreply, assign(socket, :break_duration_minutes, break_duration)}
  end

  @impl true
  def handle_event("create_room", _params, socket) do
    {:ok, name} =
      SocialPomodoro.RoomRegistry.create_room(
        socket.assigns.user_id,
        socket.assigns.duration_minutes,
        socket.assigns.num_cycles,
        socket.assigns.break_duration_minutes
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
        # Check if room is already in progress (active or break)
        # If so, navigate to room page. If in autostart, stay on lobby
        case SocialPomodoro.RoomRegistry.get_room(name) do
          {:ok, room_pid} ->
            room_state = SocialPomodoro.Room.get_raw_state(room_pid)

            if room_state.status in [:active, :break] do
              {:noreply, push_navigate(socket, to: ~p"/room/#{name}")}
            else
              {:noreply, socket}
            end

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, "Could not join room")}
    end
  end

  @impl true
  def handle_event("rejoin_room", %{"room-name" => name}, socket) do
    # If user is already in this room (my_room_name is set), just navigate
    if socket.assigns.my_room_name == name do
      {:noreply, push_navigate(socket, to: ~p"/room/#{name}")}
    else
      # User needs to rejoin the room first
      case join_room_and_update_state(socket, name, socket.assigns.user_id) do
        {:ok, socket} ->
          {:noreply, push_navigate(socket, to: ~p"/room/#{name}")}

        {:error, socket} ->
          {:noreply, put_flash(socket, :error, "Could not rejoin room")}
      end
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

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    count = SocialPomodoroWeb.Presence.list("app:global") |> map_size()
    {:noreply, assign(socket, :active_user_count, count)}
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

  defp assign_timer_defaults(socket, duration_minutes) do
    defaults = SocialPomodoro.Config.defaults_for_duration(duration_minutes)
    cycles = defaults.cycles

    break_minutes =
      if cycles == 1 do
        SocialPomodoro.Config.single_cycle_break_duration()
      else
        defaults.break_minutes
      end

    socket
    |> assign(:duration_minutes, duration_minutes)
    |> assign(:num_cycles, cycles)
    |> assign(:break_duration_minutes, break_minutes)
    |> assign(:break_options_disabled, cycles == 1)
  end

  defp pomodoro_duration_options do
    SocialPomodoro.Config.pomodoro_duration_options()
  end

  defp cycle_count_options do
    SocialPomodoro.Config.cycle_count_options()
  end

  defp break_duration_options do
    SocialPomodoro.Config.break_duration_options()
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
    <div class="navbar bg-base-300 text-neutral-content min-h-fit p-3">
      <div class="flex-1">
        <a href="/" class="block">
          <img
            src={~p"/images/logo-horizontal.png"}
            alt="focus with strangers"
            class="h-9 w-auto object-contain block md:h-16"
          />
        </a>
      </div>
      <div class="flex-none gap-2 flex">
        <button
          phx-click={SocialPomodoroWeb.CoreComponents.show_modal("feedback-modal")}
          class="btn btn-secondary btn-dash text-xs md:text-sm px-2 md:px-4"
        >
          Give Feedback
        </button>
        <button
          type="button"
          data-open-session-settings
          class="btn btn-ghost btn-square"
          title="Settings"
        >
          <Icons.gear class="w-5 h-5 fill-current" />
        </button>
      </div>
    </div>

    <div class="bg-base-100 p-2 xs:p-4 md:p-8">
      <div class="max-w-6xl mx-auto">
        <div class="grid grid-cols-1 lg:grid-cols-[1fr_auto] gap-8 mb-8">
          <!-- Left Column: Explanation -->
          <div class="card bg-base-200 relative overflow-hidden ">
            <!-- Background emoji pattern -->
            <div class="absolute inset-0 opacity-10 pointer-events-none">
              <div class="flex flex-wrap gap-4 -rotate-12 scale-200 -ml-8">
                <%= for _ <- 1..75 do %>
                  <img src="/images/emojis/1F345.svg" class="w-4 h-4" alt="" />
                  <img src="/images/emojis/E0AB.svg" class="w-4 h-4" alt="" />
                  <img src="/images/emojis/26A1.svg" class="w-4 h-4" alt="" />
                <% end %>
              </div>
            </div>

            <div class="card-body relative z-10 flex flex-col justify-center min-h-[365px]">
              <div>
                <h1 class="card-title text-4xl mb-2">Fancy a Pomodoro?</h1>
                <div class="h-1 w-24 bg-secondary rounded-full mb-6"></div>

                <div class="space-y-8">
                  <p class="text-2xl leading-relaxed">
                    Focus with strangers. Or friends.
                  </p>

                  <p class="text-xl leading-relaxed">
                    Create a room, set your timer, and get things done together.
                  </p>

                  <div class="text-secondary italic text-lg">
                    No webcam. No chat. Just work.
                  </div>
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
              num_cycles={@num_cycles}
              break_duration_minutes={@break_duration_minutes}
              break_options_disabled={@break_options_disabled}
            />
          </div>
        </div>

        <div class="card bg-base-200 ">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title">Lobby</h2>
              <div
                class="tooltip"
                data-tip={"#{@active_user_count} #{if @active_user_count == 1, do: "stranger", else: "strangers"} online"}
              >
                <div class="flex items-center gap-2 px-3 py-2 rounded-lg bg-base-100/20">
                  <.icon name="hero-user-group" class="w-5 h-5" />
                  <span class="font-semibold">{@active_user_count}</span>
                </div>
              </div>
            </div>

            <%= if Enum.empty?(@rooms) do %>
              <div class="text-center py-12">
                <p class="text-lg">
                  No one is here yet
                  <img
                    src="/images/emojis/1F97A.svg"
                    class="w-6 h-6 inline align-middle"
                    alt="🥺"
                  /> <br /> That's okay! You can focus solo!
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

    <!-- Footer -->
    <div class="bg-gradient-to-b from-base-200 to-base-300 text-center py-4 text-xs opacity-50">
      <.link navigate="/about" class="link">About</.link>
    </div>

    <.feedback_modal id="feedback-modal" username={@username}>
      <:trigger></:trigger>
    </.feedback_modal>

    <.settings_panel id="settings-panel" mode="lobby" username={@username} user_id={@user_id} />

    <div id="ambient-audio-hook" phx-hook="AmbientAudio" phx-update="ignore"></div>
    """
  end

  defp can_rejoin?(room, user_id) do
    # User can rejoin if they're a session participant but not currently in the room
    is_session_participant = Enum.member?(room.session_participants, user_id)
    is_currently_in_room = Enum.any?(room.participants, &(&1.user_id == user_id))

    is_session_participant and not is_currently_in_room
  end

  defp room_description(room) do
    count = Utils.count_with_word(length(room.participants), "person", "people")
    status = if room.status == :autostart, do: "waiting", else: "focusing"

    duration_info =
      if room.total_cycles > 1 do
        "#{room.total_cycles} × #{room.duration_minutes} min · #{room.break_duration_minutes} min breaks"
      else
        "#{room.duration_minutes} min"
      end

    "#{count} #{status} · #{duration_info}"
  end

  attr :room, :map, required: true
  attr :user_id, :string, required: true
  attr :my_room_name, :string, default: nil

  defp room_card(assigns) do
    ~H"""
    <div class={"card bg-base-100 p-2 xs:p-4
    bg-[repeating-radial-gradient(circle_at_center,rgba(255,255,255,0.05)_0,rgba(255,255,255,0.05)_2px,transparent_1px,transparent_20px)]
    bg-[size:20px_20px]
    " <>
      if @room.name == @my_room_name, do: "border-2 border-primary", else: ""}>
      <div class="card-body p-2 md:p-4 gap-3 flex flex-col justify-between min-h-48">
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
            {room_description(@room)}
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
            <%= cond do %>
              <% @room.status == :autostart -> %>
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
              <% @room.status == :break -> %>
                <div class="badge badge-soft badge-info gap-2 text-xs h-auto py-2">
                  <Icons.bell class="w-4 h-4 flex-shrink-0 fill-current" />
                  <span class="text-xs">On Break</span>
                </div>
              <% true -> %>
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
            <%= cond do %>
              <% @room.status == :autostart -> %>
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
                      Start
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
              <% @room.status == :break -> %>
                <%= cond do %>
                  <% @room.name == @my_room_name -> %>
                    <%!-- User is already in the room but viewing lobby - show rejoin to navigate back --%>
                    <button
                      phx-click="rejoin_room"
                      phx-value-room-name={@room.name}
                      phx-hook="RequestWakeLock"
                      id={"rejoin-room-btn-#{@room.name}"}
                      class="btn btn-primary btn-outline btn-sm"
                    >
                      Rejoin
                    </button>
                  <% can_rejoin?(@room, @user_id) -> %>
                    <%!-- User is an original participant who left - show rejoin --%>
                    <button
                      phx-click="rejoin_room"
                      phx-value-room-name={@room.name}
                      phx-hook="RequestWakeLock"
                      id={"rejoin-room-btn-#{@room.name}"}
                      class="btn btn-primary btn-outline btn-sm"
                    >
                      Rejoin
                    </button>
                  <% true -> %>
                    <%!-- New user joining during break --%>
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
              <% true -> %>
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
  attr :num_cycles, :integer, required: true
  attr :break_duration_minutes, :integer, required: true
  attr :break_options_disabled, :boolean, default: false

  defp user_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        
    <!-- Username Editor -->
        <div class="pb-4 border-b border-base-300">
          <!-- Avatar + username -->
          <div class="flex gap-2 items-center">
            <.participant_avatar
              user_id={@user_id}
              username={@username}
              current_user_id={@user_id}
              size="w-12"
            />
            <div class="flex-1">
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

        <div class="flex flex-col mx-auto w-full lg:w-xs relative">
          <div class="relative z-0 bg-base-200/50 p-4 rounded-box">
            <h2 class="card-title mb-4">Set your timer</h2>
            
    <!-- Pomodoro Duration -->
            <label class="label">
              <span class="label-text">Pomodoro time</span>
            </label>
            <div class="join w-full mb-4">
              <%= for minutes <- pomodoro_duration_options() do %>
                <button
                  phx-click="set_duration"
                  phx-value-minutes={minutes}
                  disabled={@my_room_name != nil}
                  class={"join-item btn flex-1 !border-2 " <> if @duration_minutes == minutes, do: "btn-primary btn-outline", else: "btn-neutral btn-outline"}
                >
                  {minutes} min
                </button>
              <% end %>
            </div>
            
    <!-- Number of Cycles -->
            <label class="label">
              <span class="label-text">Number of pomodoros</span>
            </label>
            <div class="join w-full mb-4">
              <%= for cycles <- cycle_count_options() do %>
                <button
                  phx-click="set_cycles"
                  phx-value-cycles={cycles}
                  disabled={@my_room_name != nil}
                  class={"join-item btn flex-1 !border-2 " <> if @num_cycles == cycles, do: "btn-primary btn-outline", else: "btn-neutral btn-outline"}
                >
                  {cycles}
                </button>
              <% end %>
            </div>
            
    <!-- Break Duration -->
            <label class="label">
              <span class="label-text">Break time</span>
            </label>
            <div class="relative mb-4">
              <div class="join w-full">
                <%= for minutes <- break_duration_options() do %>
                  <button
                    phx-click="set_break_duration"
                    phx-value-minutes={minutes}
                    disabled={@my_room_name != nil or @break_options_disabled}
                    class={[
                      "join-item btn flex-1 !border-2",
                      if(@break_duration_minutes == minutes,
                        do: "btn-primary btn-outline",
                        else: "btn-neutral btn-outline"
                      ),
                      if(@my_room_name != nil or @break_options_disabled,
                        do: "btn-disabled",
                        else: nil
                      )
                    ]}
                  >
                    {minutes} min
                  </button>
                <% end %>
              </div>

              <%= if @break_options_disabled do %>
                <div
                  class="absolute inset-0 z-20 flex items-center justify-center p-4 rounded-box border border-base-content/5 bg-gradient-to-br from-base-200/35 via-base-200/20 to-base-100/10 backdrop-blur-lg shadow-lg pointer-events-none"
                  role="alert"
                >
                  <div class="pointer-events-auto flex items-center gap-2 text-xs text-sm text-base-content/90">
                    <span>No breaks for a single pomodoro.</span>
                  </div>
                </div>
              <% end %>
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
