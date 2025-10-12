defmodule SocialPomodoroWeb.SessionLive do
  use SocialPomodoroWeb, :live_view
  alias SocialPomodoroWeb.Icons

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

          socket =
            socket
            |> assign(:name, name)
            |> assign(:room_state, room_state)
            |> assign(:user_id, user_id)
            |> assign(:username, username)
            |> assign(:selected_emoji, nil)
            |> assign(:is_spectator, is_spectator)

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
  def handle_event("set_working_on", %{"text" => text}, socket) do
    SocialPomodoro.Room.set_working_on(
      socket.assigns.name,
      socket.assigns.user_id,
      text
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
  def handle_event("leave_room", _params, socket) do
    SocialPomodoro.Room.leave(socket.assigns.name, socket.assigns.user_id)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:room_state, room_state}, socket) do
    # Update spectator status
    is_spectator = is_spectator?(room_state, socket.assigns.user_id)

    socket =
      socket
      |> assign(:room_state, room_state)
      |> assign(:is_spectator, is_spectator)
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
    <div class="min-h-screen bg-base-100 flex items-center justify-center p-8">
      <div class="max-w-4xl w-full">
        <%= if @is_spectator do %>
          <.spectator_view room_state={@room_state} />
        <% else %>
          <%= if @room_state.status == :active do %>
            <.active_session_view room_state={@room_state} user_id={@user_id} />
          <% end %>

          <%= if @room_state.status == :break do %>
            <.break_view room_state={@room_state} user_id={@user_id} />
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
        
    <!-- Participants with status and working_on (read-only) -->
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

  defp active_session_view(assigns) do
    # Helper to find current user's participant
    current_participant =
      Enum.find(assigns.room_state.participants, &(&1.user_id == assigns.user_id))

    assigns = assign(assigns, :current_participant, current_participant)

    ~H"""
    <div phx-hook="MaintainWakeLock" id="active-session-view">
      <div class="card bg-base-200">
        <div class="card-body text-center">
          <%= if @room_state.spectators_count > 0 do %>
            <!-- Spectator Badge -->
            <div class="flex justify-center mb-4">
              <div
                class="tooltip tooltip-bottom"
                data-tip={"#{@room_state.spectators_count} spectator#{if @room_state.spectators_count > 1, do: "s", else: ""}. They will join when the current session ends."}
              >
                <div class="badge badge-ghost gap-2">
                  <Icons.ghost class="w-4 h-4 fill-current" />
                  <span>{@room_state.spectators_count}</span>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Timer Display -->
          <.timer_display
            id="timer-display"
            seconds_remaining={@room_state.seconds_remaining}
            label="Focus time remaining"
          />
          
    <!-- Participants with status and working_on -->
          <div class="flex flex-wrap justify-center gap-6 mb-8">
            <%= for participant <- @room_state.participants do %>
              <.participant_display participant={participant} current_user_id={@user_id} />
            <% end %>
          </div>
          
    <!-- Status Emoji Buttons -->
          <p class="text-sm opacity-70 mb-2">How are you feeling?</p>
          <div class="join mb-8 mx-auto">
            <button
              phx-click="set_status"
              phx-value-emoji="1F636"
              phx-hook="MaintainWakeLock"
              id="emoji-1F636"
              class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F636", do: "btn-active"}"}
            >
              <img src="/images/emojis/1F636.svg" class="w-8 h-8 md:w-12 md:h-12" alt="😶" />
            </button>
            <button
              phx-click="set_status"
              phx-value-emoji="1FAE0"
              phx-hook="MaintainWakeLock"
              id="emoji-1FAE0"
              class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1FAE0", do: "btn-active"}"}
            >
              <img src="/images/emojis/1FAE0.svg" class="w-8 h-8 md:w-12 md:h-12" alt="🫠" />
            </button>
            <button
              phx-click="set_status"
              phx-value-emoji="1F914"
              phx-hook="MaintainWakeLock"
              id="emoji-1F914"
              class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F914", do: "btn-active"}"}
            >
              <img src="/images/emojis/1F914.svg" class="w-8 h-8 md:w-12 md:h-12" alt="🤔" />
            </button>
            <button
              phx-click="set_status"
              phx-value-emoji="1F604"
              phx-hook="MaintainWakeLock"
              id="emoji-1F604"
              class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F604", do: "btn-active"}"}
            >
              <img src="/images/emojis/1F604.svg" class="w-8 h-8 md:w-12 md:h-12" alt="😄" />
            </button>
            <button
              phx-click="set_status"
              phx-value-emoji="1F60E"
              phx-hook="MaintainWakeLock"
              id="emoji-1F60E"
              class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F60E", do: "btn-active"}"}
            >
              <img src="/images/emojis/1F60E.svg" class="w-8 h-8 md:w-12 md:h-12" alt="😎" />
            </button>
          </div>
          
    <!-- What are you working on? -->
          <%= if is_nil(@current_participant.working_on) do %>
            <div class="mb-8">
              <form phx-submit="set_working_on" class="flex gap-2 justify-center">
                <input
                  type="text"
                  name="text"
                  placeholder="What are you working on?"
                  class="input input-bordered w-full max-w-md text-base"
                  required
                />
                <button
                  type="submit"
                  phx-hook="MaintainWakeLock"
                  id="submit-working-on"
                  class="btn btn-square btn-primary"
                >
                  <Icons.submit class="w-6 h-6 fill-current" />
                </button>
              </form>
            </div>
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

  defp break_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body text-center">
        <%= if @room_state.spectators_count > 0 do %>
          <!-- Spectator Badge -->
          <div class="flex justify-center mb-4">
            <div
              class="tooltip tooltip-bottom"
              data-tip={"#{@room_state.spectators_count} spectator#{if @room_state.spectators_count > 1, do: "s", else: ""}. They will join when the current session ends."}
            >
              <div class="badge badge-ghost gap-2">
                <Icons.ghost class="w-4 h-4 fill-current" />
                <span>{@room_state.spectators_count}</span>
              </div>
            </div>
          </div>
        <% end %>

        <div class="text-6xl mb-6">🎉</div>
        <h1 class="card-title text-4xl justify-center mb-4">Great Work!</h1>
        <p class="text-xl mb-8">
          {completion_message(@room_state.duration_minutes, length(@room_state.participants))}
        </p>

        <.timer_display
          id="break-timer-display"
          seconds_remaining={@room_state.seconds_remaining}
          label="Break time remaining"
        />
        
    <!-- Participants with ready status -->
        <div class="flex justify-center gap-4 mb-8">
          <%= for participant <- @room_state.participants do %>
            <div class="text-center">
              <div class="indicator">
                <%= if participant.ready_for_next do %>
                  <span class="indicator-item badge badge-success badge-sm">✓</span>
                <% end %>
                <.participant_avatar
                  user_id={participant.user_id}
                  username={participant.username}
                  current_user_id={@user_id}
                />
              </div>
              <%= if participant.ready_for_next do %>
                <p class="text-xs text-success font-semibold mt-1">Ready!</p>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="card-actions justify-center gap-4">
          <button
            phx-click="go_again"
            class="btn btn-primary btn-lg"
          >
            Go Again Together
          </button>
          <button
            phx-click="leave_room"
            phx-hook="ReleaseWakeLock"
            id="leave-room-break"
            class="btn btn-lg text-error"
          >
            <Icons.leave class="w-5 h-5 fill-error" />
            <span class="text-error">Return to Lobby</span>
          </button>
        </div>

        <%= if Enum.any?(@room_state.participants, & &1.ready_for_next) do %>
          <p class="text-sm opacity-50 mt-6">
            Waiting for everyone to be ready...
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_time(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time(_), do: "0:00"

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

        "You focused with #{other_count} #{if other_count == 1, do: "other person", else: "other people"} for #{duration_minutes} minutes!"
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
    ~H"""
    <div>
      <div
        id={@id}
        class="text-5xl font-bold text-primary mb-2"
        phx-hook="Timer"
        data-seconds-remaining={@seconds_remaining}
      >
        {format_time(@seconds_remaining)}
      </div>
      <p class="text-content mb-8">{@label}</p>
    </div>
    """
  end

  defp emoji_to_openmoji(unicode_code) do
    "/images/emojis/#{unicode_code}.svg"
  end

  defp maybe_show_break_ending_flash(socket, room_state) do
    cond do
      room_state.status == :break && room_state.seconds_remaining == 10 ->
        put_flash(socket, :info, "Break ending soon! Returning to lobby in 10 seconds...")

      room_state.status == :break && room_state.seconds_remaining <= 0 ->
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
    not Enum.any?(room_state.session_participants, &(&1 == user_id))
  end

  attr :participant, :map, required: true
  attr :current_user_id, :string, default: nil

  defp participant_display(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 max-w-xs">
      <div class="relative">
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
      <%= if @participant.working_on do %>
        <p class="text-xs opacity-70 text-center break-words w-full">
          {@participant.working_on}
        </p>
      <% end %>
    </div>
    """
  end
end
