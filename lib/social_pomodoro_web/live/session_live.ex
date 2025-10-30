defmodule SocialPomodoroWeb.SessionLive do
  use SocialPomodoroWeb, :live_view
  alias SocialPomodoroWeb.Icons
  alias SocialPomodoroWeb.SessionParticipantComponents
  alias SocialPomodoroWeb.SessionTimerComponents

  @impl true
  def mount(params, session, socket) do
    name = params["name"]
    user_id = session["user_id"]
    username = SocialPomodoro.UserRegistry.get_username(user_id) || "Unknown User"

    case SocialPomodoro.RoomRegistry.get_room(name) do
      {:ok, _pid} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "room:#{name}")
          Phoenix.PubSub.subscribe(SocialPomodoro.PubSub, "user:#{user_id}")

          # Track this user's presence
          SocialPomodoroWeb.Presence.track(self(), "app:global", user_id, %{
            username: username
          })

          # Join the room when connected (handles refreshes and direct navigation)
          SocialPomodoro.Room.join(name, user_id)
        end

        # Get room state after joining
        {:ok, pid} = SocialPomodoro.RoomRegistry.get_room(name)
        room_state = SocialPomodoro.Room.get_state(pid)

        # If room is in autostart, redirect to lobby
        if room_state.status == :autostart do
          {:ok, push_navigate(socket, to: ~p"/")}
        else
          # Check if user is a spectator
          is_spectator = spectator?(room_state, user_id)

          # Use completion message from room state
          completion_msg = room_state.completion_message

          # Find current participant
          current_participant =
            Enum.find(room_state.participants, &(&1.user_id == user_id))

          socket =
            socket
            |> assign(:name, name)
            |> assign(:room_state, room_state)
            |> assign(:user_id, user_id)
            |> assign(:username, username)
            |> assign(:selected_emoji, nil)
            |> assign(:is_spectator, is_spectator)
            |> assign(:completion_message, completion_msg)
            |> assign(:current_participant, current_participant)
            |> assign(:selected_tab, :todo)
            |> push_event("session_status_changed", %{status: Atom.to_string(room_state.status)})

          {:ok, socket}
        end

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("start_session", _params, socket) do
    SocialPomodoro.Room.start_session(socket.assigns.name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_todo", %{"text" => text}, socket) do
    SocialPomodoro.Room.add_todo(
      socket.assigns.name,
      socket.assigns.user_id,
      text
    )

    {:noreply, push_event(socket, "clear-form", %{id: "todo-form"})}
  end

  @impl true
  def handle_event("toggle_todo", %{"todo_id" => todo_id}, socket) do
    SocialPomodoro.Room.toggle_todo(
      socket.assigns.name,
      socket.assigns.user_id,
      todo_id
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_todo", %{"todo_id" => todo_id}, socket) do
    SocialPomodoro.Room.delete_todo(
      socket.assigns.name,
      socket.assigns.user_id,
      todo_id
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_status", %{"emoji" => emoji}, socket) do
    SocialPomodoro.Room.set_status(
      socket.assigns.name,
      socket.assigns.user_id,
      emoji
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("go_again", _params, socket) do
    SocialPomodoro.Room.go_again(socket.assigns.name, socket.assigns.user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_chat_message", %{"text" => text}, socket) do
    SocialPomodoro.Room.send_chat_message(
      socket.assigns.name,
      socket.assigns.user_id,
      text
    )

    {:noreply, push_event(socket, "clear-form", %{id: "chat-form"})}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_atom(tab)
    # Only allow switching to chat during break
    if tab_atom == :chat and socket.assigns.room_state.status != :break do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :selected_tab, tab_atom)}
    end
  end

  @impl true
  def handle_event("leave_room", _params, socket) do
    SocialPomodoro.Room.leave(socket.assigns.name, socket.assigns.user_id)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("update_username", %{"username" => username}, socket) do
    user_id = socket.assigns.user_id
    SocialPomodoro.UserRegistry.register_or_update_user(user_id, username)

    # Just update @username - the component uses this directly now
    {:noreply, assign(socket, :username, username)}
  end

  @impl true
  # TODO: major refactor needed. Most of these are not necessary. Only tick is necessary?
  def handle_info({:room_state, room_state}, socket) do
    # Update spectator status
    is_spectator = spectator?(room_state, socket.assigns.user_id)

    # Use completion message from room state (generated once on the server)
    completion_msg = room_state.completion_message

    # Find current participant
    current_participant =
      Enum.find(room_state.participants, &(&1.user_id == socket.assigns.user_id))

    # Fallback: If current_participant is nil but we're not a spectator,
    # create a minimal participant object to prevent UI from breaking.
    # This handles potential race conditions (especially on Safari).
    current_participant =
      if current_participant == nil and not is_spectator do
        # Create a minimal participant with empty state
        %{
          user_id: socket.assigns.user_id,
          username: socket.assigns.username,
          ready_for_next: false,
          todos: [],
          status_emoji: nil,
          status_message: nil
        }
      else
        current_participant
      end

    # Reset tab to todo when transitioning from break to active
    selected_tab =
      if socket.assigns.room_state.status == :break and room_state.status == :active do
        :todo
      else
        socket.assigns.selected_tab
      end

    socket =
      socket
      |> assign(:room_state, room_state)
      |> assign(:is_spectator, is_spectator)
      |> assign(:completion_message, completion_msg)
      |> assign(:current_participant, current_participant)
      |> assign(:selected_tab, selected_tab)
      |> maybe_show_spectator_joining_flash(room_state, is_spectator)
      |> maybe_show_break_ending_flash(room_state)
      |> push_event("session_status_changed", %{status: Atom.to_string(room_state.status)})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:username_updated, user_id, username}, socket) do
    if socket.assigns.user_id == user_id do
      # Current user - just update @username (used directly by component)
      {:noreply, assign(socket, :username, username)}
    else
      # Other participant - update their username in room_state.participants
      updated_room_state =
        update_participant_username(socket.assigns.room_state, user_id, username)

      {:noreply, assign(socket, :room_state, updated_room_state)}
    end
  end

  @impl true
  def handle_info({:session_started, _room_name}, socket) do
    # Ignore if already on session page
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="flex items-center justify-center min-h-screen py-4 px-2 md:px-8">
        <div class="max-w-4xl w-full">
          <%= case view_mode(assigns) do %>
            <% :spectator -> %>
              <.spectator_view room_state={@room_state} />
            <% :active -> %>
              <.active_session_view
                room_state={@room_state}
                user_id={@user_id}
                username={@username}
                current_participant={@current_participant}
                selected_tab={@selected_tab}
              />
            <% :break -> %>
              <.break_view
                room_state={@room_state}
                user_id={@user_id}
                username={@username}
                completion_message={@completion_message}
                current_participant={@current_participant}
                selected_tab={@selected_tab}
              />
            <% :none -> %>
              nil
          <% end %>
        </div>
      </div>
    </div>

    <.settings_panel id="settings-panel" mode="session" username={@username} user_id={@user_id} />

    <div id="ambient-audio-hook" phx-hook="AmbientAudio" phx-update="ignore"></div>
    """
  end

  attr :room_state, :map, required: true

  def spectator_view(assigns) do
    ~H"""
    <div class="card bg-base-200 relative">
      <!-- Settings Button -->
      <div class="absolute top-4 right-4">
        <button
          data-open-session-settings
          class="btn btn-ghost btn-sm btn-circle"
          title="Settings"
        >
          <Icons.gear class="w-5 h-5 fill-current" />
        </button>
      </div>

      <div class="card-body text-center p-2 md:pd-4">
        <div class="text-6xl mb-6">
          <Icons.ghost class="w-24 h-24 mx-auto fill-base-content opacity-50" />
        </div>
        <h1 class="card-title text-3xl justify-center mb-4">You're a spectator</h1>
        <p class="text-xl mb-8">
          Watch the session in progress. You'll be able to join during the break.
        </p>

        <SessionTimerComponents.timer_display
          id="spectator-timer-display"
          seconds_remaining={@room_state.seconds_remaining}
          label={
            if @room_state.status == :active, do: "Focus time remaining", else: "Break time remaining"
          }
        />
        
    <!-- Participants with status and status_message (read-only) -->
        <div class="flex flex-col items-center gap-4 mb-8">
          <%= for participant <- @room_state.participants do %>
            <SessionParticipantComponents.participant_display
              participant={participant}
              is_break={@room_state.status == :break}
            />
          <% end %>
        </div>

        <p class="text-sm opacity-70">
          Interactions are disabled while spectating
        </p>
      </div>
    </div>
    <!-- Leave Button for Spectator -->
    <div class="flex justify-center mt-4">
      <button
        phx-click="leave_room"
        phx-hook="ReleaseWakeLock"
        id="leave-room-spectator"
        class="btn btn-ghost btn-sm text-error"
      >
        <Icons.leave class="w-4 h-4 fill-error" />
        <span class="text-error">Leave</span>
      </button>
    </div>
    """
  end

  defp update_participant_username(room_state, user_id, username) do
    updated_participants =
      Enum.map(room_state.participants, fn participant ->
        if participant.user_id == user_id do
          Map.put(participant, :username, username)
        else
          participant
        end
      end)

    Map.put(room_state, :participants, updated_participants)
  end

  attr :room_state, :map, required: true
  attr :user_id, :string, required: true
  attr :username, :string, required: true
  attr :current_participant, :map, required: true
  attr :selected_tab, :atom, required: true

  defp active_session_view(assigns) do
    # Separate current user from other participants
    other_participants =
      Enum.reject(assigns.room_state.participants, &(&1.user_id == assigns.user_id))

    # Define active session emoji set
    active_emojis = [
      %{code: "1F636", path: "/images/emojis/1F636.svg", alt: "😶"},
      %{code: "1FAE0", path: "/images/emojis/1FAE0.svg", alt: "🫠"},
      %{code: "1F914", path: "/images/emojis/1F914.svg", alt: "🤔"},
      %{code: "1F604", path: "/images/emojis/1F604.svg", alt: "😄"},
      %{code: "1F60E", path: "/images/emojis/1F60E.svg", alt: "😎"}
    ]

    # Calculate task count (handle nil current_participant for spectators)
    {completed_count, total_count} =
      if assigns.current_participant do
        todos = Map.get(assigns.current_participant, :todos, [])
        {Enum.count(todos, & &1.completed), length(todos)}
      else
        {0, 0}
      end

    assigns =
      assigns
      |> assign(:other_participants, other_participants)
      |> assign(:active_emojis, active_emojis)
      |> assign(:completed_count, completed_count)
      |> assign(:total_count, total_count)

    ~H"""
    <div phx-hook="MaintainWakeLock" id="active-session-view">
      <div class="card bg-base-200 relative">
        <!-- Settings Button -->
        <div class="absolute top-4 right-4">
          <button
            data-open-session-settings
            class="btn btn-ghost btn-sm btn-circle"
            title="Settings"
          >
            <Icons.gear class="w-5 h-5 fill-current" />
          </button>
        </div>

        <div class="card-body text-center p-2 md:pd-4">
          <!-- Cycle Progress & Spectator Badge -->
          <div class="flex justify-center items-center gap-4 mb-2 md:mb-4">
            <%= if @room_state.total_cycles > 1 do %>
              <div class="text-sm opacity-70 flex items-center gap-1">
                <img src="/images/emojis/1F345.svg" class="w-4 h-4 inline" alt="🍅" />
                <span>{@room_state.current_cycle} of {@room_state.total_cycles}</span>
              </div>
            <% end %>

            <%= if @room_state.spectators_count > 0 do %>
              <div
                class="tooltip tooltip-bottom"
                data-tip={"#{@room_state.spectators_count} spectator#{if @room_state.spectators_count > 1, do: "s", else: ""}. They will join when the current session ends."}
              >
                <div class="badge badge-ghost gap-2">
                  <Icons.ghost class="w-4 h-4 fill-current" />
                  <span>{@room_state.spectators_count}</span>
                </div>
              </div>
            <% end %>
          </div>
          
    <!-- Timer Display -->
          <SessionTimerComponents.timer_display
            id="timer-display"
            seconds_remaining={@room_state.seconds_remaining}
            label="Focus time remaining"
          />
          
    <!-- Other Participants -->
          <SessionParticipantComponents.other_participants_section
            other_participants={@other_participants}
            is_break={false}
          />
        </div>
        
    <!-- Current User Card: Avatar, Status Emojis, Tabs -->
        <%= if @current_participant do %>
          <SessionParticipantComponents.current_user_card
            current_participant={@current_participant}
            status_emojis={@active_emojis}
            room_state={@room_state}
            selected_tab={@selected_tab}
            placeholder="What are you working on?"
            is_break={false}
            emoji_id_prefix=""
            completed_count={@completed_count}
            total_count={@total_count}
            user_id={@user_id}
            username={@username}
          />
        <% end %>
      </div>
      
    <!-- Leave Button -->
      <div class="flex justify-center mt-4">
        <button
          phx-click="leave_room"
          phx-hook="ReleaseWakeLock"
          id="leave-room-active"
          class="btn btn-ghost btn-sm text-error"
        >
          <Icons.leave class="w-4 h-4 fill-error" />
          <span class="text-error">Leave</span>
        </button>
      </div>
    </div>
    """
  end

  attr :room_state, :map, required: true
  attr :user_id, :string, required: true
  attr :username, :string, required: true
  attr :completion_message, :string, required: true
  attr :current_participant, :map, required: true
  attr :selected_tab, :atom, required: true

  defp break_view(assigns) do
    # Determine if this is the final break
    is_final_break = assigns.room_state.current_cycle == assigns.room_state.total_cycles

    # Separate current user from other participants
    other_participants =
      Enum.reject(assigns.room_state.participants, &(&1.user_id == assigns.user_id))

    # Define break emoji set
    break_emojis = [
      %{code: "1F635-200D-1F4AB", path: "/images/emojis/1F635-200D-1F4AB.svg", alt: "😵‍💫"},
      %{code: "1F62E-200D-1F4A8", path: "/images/emojis/1F62E-200D-1F4A8.svg", alt: "😮‍💨"},
      %{code: "1F60C", path: "/images/emojis/1F60C.svg", alt: "😌"},
      %{code: "2615", path: "/images/emojis/2615.svg", alt: "☕"},
      %{code: "1F4AA", path: "/images/emojis/1F4AA.svg", alt: "💪"}
    ]

    # Calculate task count (handle nil current_participant for spectators)
    {completed_count, total_count} =
      if assigns.current_participant do
        todos = Map.get(assigns.current_participant, :todos, [])
        {Enum.count(todos, & &1.completed), length(todos)}
      else
        {0, 0}
      end

    assigns =
      assigns
      |> assign(:is_final_break, is_final_break)
      |> assign(:other_participants, other_participants)
      |> assign(:break_emojis, break_emojis)
      |> assign(:completed_count, completed_count)
      |> assign(:total_count, total_count)

    ~H"""
    <div class="card bg-base-200 relative">
      <!-- Settings Button -->
      <div class="absolute top-4 right-4">
        <button
          data-open-session-settings
          class="btn btn-ghost btn-sm btn-circle"
          title="Settings"
        >
          <Icons.gear class="w-5 h-5 fill-current" />
        </button>
      </div>

      <div class="card-body text-center p-2 md:pd-4">
        <!-- Cycle Progress -->
        <%= if @room_state.total_cycles > 1 do %>
          <div class="text-sm opacity-70 mb-2 flex items-center justify-center gap-1">
            <%= if @is_final_break do %>
              <img src="/images/emojis/1F345.svg" class="w-4 h-4 inline" alt="🍅" />
              <span>All cycles complete!</span>
            <% else %>
              <img src="/images/emojis/1F345.svg" class="w-4 h-4 inline" alt="🍅" />
              <span>Cycle {@room_state.current_cycle} of {@room_state.total_cycles} complete</span>
            <% end %>
          </div>
        <% end %>

        <h1 class="card-title text-4xl justify-center mb-4">
          <%= if @is_final_break do %>
            <img src="/images/emojis/1F389.svg" class="w-12 h-12" alt="🎉" />
            <span>Amazing Work!</span>
          <% else %>
            <img src="/images/emojis/1F389.svg" class="w-12 h-12" alt="🎉" />
            <span>Great Work!</span>
          <% end %>
        </h1>
        <p class="text-xl mb-8">
          {@completion_message}
        </p>

        <SessionTimerComponents.timer_display
          id="break-timer-display"
          seconds_remaining={@room_state.seconds_remaining}
          label="Break time remaining"
        />

        <SessionParticipantComponents.other_participants_section
          other_participants={@other_participants}
          is_break={true}
        />
      </div>

      <%= if @current_participant do %>
        <SessionParticipantComponents.current_user_card
          current_participant={@current_participant}
          status_emojis={@break_emojis}
          room_state={@room_state}
          selected_tab={@selected_tab}
          placeholder="What are you working on?"
          is_break={true}
          emoji_id_prefix="break-"
          completed_count={@completed_count}
          total_count={@total_count}
          user_id={@user_id}
          username={@username}
        />
      <% end %>
    </div>

    <div class="mt-10 flex flex-col items-center gap-6">
      <div class="flex flex-col sm:flex-row justify-center gap-4 w-full sm:w-auto">
        <%= if not @is_final_break do %>
          <button
            phx-click="go_again"
            class="btn btn-primary w-full sm:w-auto"
          >
            Skip Break
          </button>
        <% end %>
        <button
          phx-click="leave_room"
          phx-hook="ReleaseWakeLock"
          id="leave-room-break"
          class="btn text-error w-full sm:w-auto"
        >
          <Icons.leave class="w-5 h-5 fill-error" />
          <span class="text-error">Return to Lobby</span>
        </button>
      </div>

      <%= if not @is_final_break and Enum.any?(@room_state.participants, & &1.ready_for_next) do %>
        <p class="text-sm opacity-50 text-center">
          Waiting for everyone to skip break...
        </p>
      <% end %>
    </div>
    """
  end

  defp maybe_show_break_ending_flash(socket, room_state) do
    is_final_break = room_state.current_cycle == room_state.total_cycles

    cond do
      room_state.status == :break && room_state.seconds_remaining == 10 && is_final_break ->
        put_flash(socket, :info, "Break ending soon! Returning to lobby in 10 seconds...")

      room_state.status == :break && room_state.seconds_remaining <= 0 && is_final_break ->
        push_navigate(socket, to: ~p"/")

      true ->
        socket
    end
  end

  defp maybe_show_spectator_joining_flash(socket, room_state, is_spectator) do
    if is_spectator and room_state.status == :active and room_state.seconds_remaining == 10 do
      put_flash(socket, :info, "You'll join the room during the break")
    else
      socket
    end
  end

  defp view_mode(%{is_spectator: true}), do: :spectator

  defp view_mode(%{room_state: %{status: status}}) when status in [:active, :break], do: status

  defp view_mode(_), do: :none

  defp spectator?(room_state, user_id) do
    case room_state.status do
      :break ->
        # During break, all participants are non-spectators
        false

      _ ->
        # For other statuses, check session participants
        not Enum.any?(room_state.session_participants, &(&1 == user_id))
    end
  end
end
