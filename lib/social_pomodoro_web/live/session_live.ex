defmodule SocialPomodoroWeb.SessionLive do
  use SocialPomodoroWeb, :live_view
  alias SocialPomodoroWeb.Icons
  alias SocialPomodoro.Utils

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
          is_spectator = is_spectator?(room_state, user_id)

          # Set completion message if room is already in break
          completion_msg =
            if room_state.status == :break do
              completion_message(
                room_state.duration_minutes,
                length(room_state.session_participants)
              )
            else
              nil
            end

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
  # TODO: major refactor needed. Most of these are not necessary. Only tick is necessary?
  def handle_info({:room_state, room_state}, socket) do
    # Update spectator status
    is_spectator = is_spectator?(room_state, socket.assigns.user_id)

    # Update completion message only when transitioning INTO break
    # (not on every update during break, to avoid regenerating random messages)
    completion_msg =
      if socket.assigns.room_state.status != :break and room_state.status == :break do
        completion_message(room_state.duration_minutes, length(room_state.session_participants))
      else
        # Keep existing message if already in break
        socket.assigns.completion_message
      end

    # Find current participant
    current_participant =
      Enum.find(room_state.participants, &(&1.user_id == socket.assigns.user_id))

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

    {:noreply, socket}
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
  def handle_info({:session_started, _room_name}, socket) do
    # Ignore if already on session page
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Leave room when LiveView process terminates (e.g., navigation away)
    SocialPomodoro.Room.leave(socket.assigns.name, socket.assigns.user_id)
    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 flex items-center justify-center p-4 md:px-8">
      <div class="max-w-4xl w-full">
        <%= if @is_spectator do %>
          <.spectator_view room_state={@room_state} />
        <% else %>
          <%= if @room_state.status == :active do %>
            <.active_session_view
              room_state={@room_state}
              user_id={@user_id}
              current_participant={@current_participant}
              selected_tab={@selected_tab}
            />
          <% end %>

          <%= if @room_state.status == :break do %>
            <.break_view
              room_state={@room_state}
              user_id={@user_id}
              completion_message={@completion_message}
              current_participant={@current_participant}
              selected_tab={@selected_tab}
            />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :room_state, :map, required: true

  def spectator_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body text-center">
        <div class="text-6xl mb-6">
          <Icons.ghost class="w-24 h-24 mx-auto fill-base-content opacity-50" />
        </div>
        <h1 class="card-title text-3xl justify-center mb-4">You're a spectator</h1>
        <p class="text-xl mb-8">
          Watch the session in progress. You'll be able to join during the break.
        </p>

        <.timer_display
          id="spectator-timer-display"
          seconds_remaining={@room_state.seconds_remaining}
          label={
            if @room_state.status == :active, do: "Focus time remaining", else: "Break time remaining"
          }
        />
        
    <!-- Participants with status and status_message (read-only) -->
        <div class="flex flex-wrap justify-center gap-6 mb-8">
          <%= for participant <- @room_state.participants do %>
            <.participant_display participant={participant} />
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

  attr :room_state, :map, required: true
  attr :user_id, :string, required: true
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
      <div class="card bg-base-200">
        <div class="card-body text-center">
          <!-- Cycle Progress & Spectator Badge -->
          <div class="flex justify-center items-center gap-4 mb-4">
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
          
    <!-- Other Participants -->
          <.other_participants_section
            other_participants={@other_participants}
            show_ready={false}
          />
          
    <!-- Timer Display -->
          <.timer_display
            id="timer-display"
            seconds_remaining={@room_state.seconds_remaining}
            label="Focus time remaining"
          />
          
    <!-- Horizontal Layout: Avatar, Status Emojis, Tabs -->
          <%= if @current_participant do %>
            <.horizontal_session_layout
              current_participant={@current_participant}
              status_emojis={@active_emojis}
              room_state={@room_state}
              selected_tab={@selected_tab}
              placeholder="What are you working on?"
              show_ready={false}
              emoji_id_prefix=""
              completed_count={@completed_count}
              total_count={@total_count}
              user_id={@user_id}
            />
          <% end %>
        </div>
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
    <div class="card bg-base-200">
      <div class="card-body text-center">
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
        
    <!-- Other Participants -->
        <.other_participants_section
          other_participants={@other_participants}
          show_ready={true}
        />

        <.timer_display
          id="break-timer-display"
          seconds_remaining={@room_state.seconds_remaining}
          label="Break time remaining"
        />
        
    <!-- Horizontal Layout: Avatar, Status Emojis, Tabs -->
        <%= if @current_participant do %>
          <.horizontal_session_layout
            current_participant={@current_participant}
            status_emojis={@break_emojis}
            room_state={@room_state}
            selected_tab={@selected_tab}
            placeholder="What are you working on?"
            show_ready={true}
            emoji_id_prefix="break-"
            completed_count={@completed_count}
            total_count={@total_count}
            user_id={@user_id}
          />
        <% end %>

        <div class="card-actions justify-center gap-4">
          <%= if not @is_final_break do %>
            <button
              phx-click="go_again"
              class="btn btn-primary"
            >
              Skip Break
            </button>
          <% end %>
          <button
            phx-click="leave_room"
            phx-hook="ReleaseWakeLock"
            id="leave-room-break"
            class="btn text-error"
          >
            <Icons.leave class="w-5 h-5 fill-error" />
            <span class="text-error">Return to Lobby</span>
          </button>
        </div>

        <%= if not @is_final_break and Enum.any?(@room_state.participants, & &1.ready_for_next) do %>
          <p class="text-sm opacity-50 mt-6">
            Waiting for everyone to skip break...
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp completion_message(duration_minutes, participant_count) do
    cond do
      participant_count == 1 ->
        # Random message for solo sessions
        Enum.random([
          "You focused solo for #{duration_minutes} minutes!",
          "Flying solo today - nice work!",
          "Solo focus session complete!",
          "You stayed focused for #{duration_minutes} minutes!"
        ])

      true ->
        # Message for group sessions
        other_count = participant_count - 1

        "You focused with #{Utils.other_people(other_count)} for #{duration_minutes} minutes!"
    end
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

  attr :id, :string, required: true
  attr :seconds_remaining, :integer, required: true
  attr :label, :string, required: true

  defp timer_display(assigns) do
    assigns = assign(assigns, :countdown_segments, countdown_segments(assigns.seconds_remaining))

    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div
        id={@id}
        class="flex justify-center gap-6"
        phx-hook="Timer"
        data-seconds-remaining={@seconds_remaining}
      >
        <%= for {unit, value} <- @countdown_segments do %>
          <div class="flex flex-col items-center gap-1" data-countdown-segment={Atom.to_string(unit)}>
            <span class="countdown font-mono text-5xl">
              <span
                data-countdown-value
                style={"--value:#{value};"}
                aria-live="polite"
                aria-label={Integer.to_string(value)}
              >
                {value}
              </span>
            </span>
            <span class="text-xs font-semibold uppercase tracking-[0.35em] text-base-content/60">
              {countdown_label(unit)}
            </span>
          </div>
        <% end %>
      </div>
      <p class="text-sm uppercase tracking-[0.35em] text-base-content/50 text-center">{@label}</p>
    </div>
    """
  end

  defp countdown_segments(seconds) when is_integer(seconds) do
    safe_seconds = max(seconds, 0)
    minutes = div(safe_seconds, 60)
    secs = rem(safe_seconds, 60)

    [
      {:minutes, minutes},
      {:seconds, secs}
    ]
  end

  defp countdown_segments(_seconds) do
    [
      {:minutes, 0},
      {:seconds, 0}
    ]
  end

  defp countdown_label(:minutes), do: "Min"
  defp countdown_label(:seconds), do: "Sec"

  defp emoji_to_openmoji(unicode_code) do
    "/images/emojis/#{unicode_code}.svg"
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

  defp is_spectator?(room_state, user_id) do
    case room_state.status do
      :break ->
        # During break, all participants are non-spectators
        false

      _ ->
        # For other statuses, check session participants
        not Enum.any?(room_state.session_participants, &(&1 == user_id))
    end
  end

  # Reusable Components

  attr :participant, :map, required: true
  attr :show_ready, :boolean, default: false

  defp current_user_avatar_with_status(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 flex-shrink-0">
      <p class="font-semibold text-center">{@participant.username}</p>
      <div class="relative">
        <.avatar
          user_id={@participant.user_id}
          username={@participant.username}
          size="w-20"
          class="ring-primary ring-offset-base-100 rounded-full ring-2 ring-offset-2"
        />
        <%= if @participant.status_emoji do %>
          <span class="absolute -bottom-2 -right-2 bg-base-100 rounded-full w-10 h-10 flex items-center justify-center border-2 border-base-100">
            <img
              src={emoji_to_openmoji(@participant.status_emoji)}
              class="w-10 h-10"
              alt={@participant.status_emoji}
            />
          </span>
        <% end %>
      </div>
      <p class="text-sm opacity-70">You</p>
      <%= if @show_ready && @participant.ready_for_next do %>
        <p class="text-xs text-success font-semibold">Ready!</p>
      <% end %>
    </div>
    """
  end

  attr :current_participant, :map, required: true
  attr :status_emojis, :list, required: true
  attr :id_prefix, :string, default: ""

  defp status_emoji_selector(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 flex-shrink-0">
      <div class="grid grid-cols-3 gap-2">
        <%= for emoji <- @status_emojis do %>
          <button
            phx-click="set_status"
            phx-value-emoji={emoji.code}
            phx-hook="MaintainWakeLock"
            id={"#{@id_prefix}emoji-#{emoji.code}"}
            class={"btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == emoji.code, do: "btn-active"}"}
          >
            <img src={emoji.path} class="w-8 h-8 md:w-10 md:h-10" alt={emoji.alt} />
          </button>
        <% end %>
      </div>
      <p class="text-sm opacity-70">Status</p>
    </div>
    """
  end

  attr :current_participant, :map, required: true
  attr :status_emojis, :list, required: true
  attr :room_state, :map, required: true
  attr :selected_tab, :atom, required: true
  attr :placeholder, :string, default: "What are you working on?"
  attr :show_ready, :boolean, default: false
  attr :emoji_id_prefix, :string, default: ""
  attr :completed_count, :integer, required: true
  attr :total_count, :integer, required: true
  attr :user_id, :string, required: true

  defp horizontal_session_layout(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center gap-4 mb-8 w-full">
      <!-- User Avatar & Status (Horizontal) -->
      <div class="w-full">
        <div class="card bg-base-300 p-4">
          <div class="flex flex-col gap-3">
            <div class="text-center text-sm opacity-70">
              {@completed_count}/{@total_count} tasks
            </div>
            <div class="flex flex-row items-center justify-center gap-4">
              <.current_user_avatar_with_status
                participant={@current_participant}
                show_ready={@show_ready}
              />
              <.status_emoji_selector
                current_participant={@current_participant}
                status_emojis={@status_emojis}
                id_prefix={@emoji_id_prefix}
              />
            </div>
          </div>
        </div>
      </div>
      
    <!-- Tabs and Content -->
      <div class="w-full">
        <.tabs_with_content
          room_state={@room_state}
          selected_tab={@selected_tab}
          current_participant={@current_participant}
          placeholder={@placeholder}
          user_id={@user_id}
        />
      </div>
    </div>
    """
  end

  attr :other_participants, :list, required: true
  attr :show_ready, :boolean, default: false

  defp other_participants_section(assigns) do
    ~H"""
    <%= if length(@other_participants) > 0 do %>
      <div class="divider">Other Participants</div>
      <div class="flex flex-wrap justify-center gap-6 mb-4">
        <%= for participant <- @other_participants do %>
          <.participant_display participant={participant} show_ready={@show_ready} />
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :participant, :map, required: true
  attr :status_emoji, :string, default: nil

  defp current_user_display(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 mb-6">
      <div class="relative">
        <.avatar
          user_id={@participant.user_id}
          username={@participant.username}
          size="w-20"
          class="ring-primary ring-offset-base-100 rounded-full ring-2 ring-offset-2"
        />
        <%= if @status_emoji do %>
          <span class="absolute -bottom-2 -right-2 bg-base-100 rounded-full w-10 h-10 flex items-center justify-center border-2 border-base-100">
            <img
              src={emoji_to_openmoji(@status_emoji)}
              class="w-10 h-10"
              alt={@status_emoji}
            />
          </span>
        <% end %>
      </div>
      <p class="font-semibold text-center">{@participant.username}</p>
    </div>
    """
  end

  attr :participant, :map, required: true
  attr :current_user_id, :string, default: nil
  attr :show_ready, :boolean, default: false

  defp participant_display(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 max-w-xs">
      <div class="relative">
        <div class={if @show_ready, do: "indicator", else: ""}>
          <%= if @show_ready && @participant.ready_for_next do %>
            <span class="indicator-item badge badge-success badge-sm">✓</span>
          <% end %>
          <.avatar
            user_id={@participant.user_id}
            username={@participant.username}
            size="w-16"
            class={
              if @current_user_id && @participant.user_id == @current_user_id do
                "ring-primary ring-offset-base-100 rounded-full ring-2 ring-offset-2"
              else
                ""
              end
            }
          />
        </div>
        <%= if @participant.status_emoji do %>
          <span class="absolute -bottom-2 -right-2 bg-base-100 rounded-full w-8 h-8 flex items-center justify-center border-2 border-base-100">
            <img
              src={emoji_to_openmoji(@participant.status_emoji)}
              class="w-8 h-8"
              alt={@participant.status_emoji}
            />
          </span>
        <% end %>
      </div>
      <p class="font-semibold text-center text-sm">{@participant.username}</p>
      <%= if @participant.todos && length(@participant.todos) > 0 do %>
        <div class="text-xs text-center w-full max-w-xs space-y-1">
          <%= for todo <- @participant.todos do %>
            <div class="flex items-center gap-2 justify-center">
              <input
                type="checkbox"
                checked={todo.completed}
                disabled
                class="checkbox checkbox-xs"
              />
              <span class={if todo.completed, do: "line-through opacity-50", else: ""}>
                {todo.text}
              </span>
            </div>
          <% end %>
        </div>
      <% end %>
      <%= if @show_ready && @participant.ready_for_next do %>
        <p class="text-xs text-success font-semibold">Ready!</p>
      <% end %>
    </div>
    """
  end

  attr :current_participant, :map, required: true
  attr :max_todos, :integer, required: true
  attr :placeholder, :string, default: "What are you working on?"

  defp todo_list(assigns) do
    todos = Map.get(assigns.current_participant, :todos, [])
    todos_count = length(todos)
    at_max = todos_count >= assigns.max_todos

    assigns =
      assigns
      |> assign(:todos, todos)
      |> assign(:todos_count, todos_count)
      |> assign(:at_max, at_max)

    ~H"""
    <div class="flex flex-col gap-2 items-center w-full max-w-md mx-auto">
      <!-- Todo items -->
      <%= if @todos_count > 0 do %>
        <ul class="list bg-base-100 rounded-box shadow-md w-full max-w-xs mb-4">
          <%= for todo <- @todos do %>
            <li class="list-row" id={"todo-#{todo.id}"}>
              <div>
                <input
                  type="checkbox"
                  checked={todo.completed}
                  phx-click="toggle_todo"
                  phx-value-todo_id={todo.id}
                  class="checkbox checkbox-sm transition-transform duration-200"
                />
              </div>
              <div class="list-col-grow">
                <span class={
                  [
                    "text-sm transition-all duration-200",
                    if(todo.completed, do: "line-through opacity-50", else: "")
                  ]
                  |> Enum.join(" ")
                }>
                  {todo.text}
                </span>
              </div>
              <button
                phx-click="delete_todo"
                phx-value-todo_id={todo.id}
                phx-hook="MaintainWakeLock"
                id={"delete-todo-#{todo.id}"}
                class="btn btn-ghost btn-xs btn-square group"
              >
                <Icons.trash class="w-4 h-4 fill-neutral group-hover:fill-error" />
              </button>
            </li>
          <% end %>
        </ul>
      <% end %>
      
    <!-- Add todo form -->
      <form
        id="todo-form"
        phx-submit="add_todo"
        phx-hook="ClearForm"
        class="flex gap-2 w-full justify-center"
      >
        <input
          type="text"
          name="text"
          placeholder={@placeholder}
          class="input input-bordered w-full max-w-xs text-base"
          maxlength="30"
          required
          disabled={@at_max}
        />
        <button
          type="submit"
          phx-hook="MaintainWakeLock"
          id="add-todo-button"
          class="btn btn-square btn-primary"
          disabled={@at_max}
        >
          <Icons.submit class="w-6 h-6 fill-current" />
        </button>
      </form>
      <%= if @at_max do %>
        <p class="text-xs opacity-50">Max {@max_todos} todos reached</p>
      <% end %>
    </div>
    """
  end

  attr :room_state, :map, required: true
  attr :selected_tab, :atom, required: true
  attr :current_participant, :map, required: true
  attr :placeholder, :string, default: "What are you working on?"
  attr :user_id, :string, required: true

  defp tabs_with_content(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-lift tabs-lg">
      <input
        type="radio"
        name="session_tabs"
        class="tab"
        aria-label="Todo"
        checked={@selected_tab == :todo}
        phx-click="switch_tab"
        phx-value-tab="todo"
      />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 p-6">
        <.todo_list
          current_participant={@current_participant}
          max_todos={SocialPomodoro.Config.max_todos_per_user()}
          placeholder={@placeholder}
        />
      </div>

      <input
        type="radio"
        name="session_tabs"
        class="tab"
        aria-label="Chat"
        checked={@selected_tab == :chat}
        disabled={@room_state.status != :break}
        phx-click="switch_tab"
        phx-value-tab="chat"
      />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 p-6">
        <div class="flex flex-col gap-4 items-center w-full max-w-md mx-auto">
          <!-- Chat Messages Display (only current user's messages, max 3) -->
          <% user_messages = Map.get(@room_state.chat_messages, @user_id, []) %>
          <%= if length(user_messages) > 0 do %>
            <div class="w-full max-w-xs space-y-2 mb-4">
              <%= for message <- user_messages do %>
                <div class="chat chat-start">
                  <div class="chat-bubble chat-bubble-secondary">
                    {message.text}
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
          
    <!-- Chat Input Form -->
          <form
            id="chat-form"
            phx-submit="send_chat_message"
            phx-hook="ClearForm"
            class="flex gap-2 w-full justify-center"
          >
            <input
              type="text"
              name="text"
              placeholder="Say something..."
              class="input input-bordered w-full max-w-xs text-base"
              maxlength="50"
              required
            />
            <button
              type="submit"
              phx-hook="MaintainWakeLock"
              id="send-chat-button"
              class="btn btn-square btn-primary"
            >
              <Icons.submit class="w-6 h-6 fill-current" />
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
