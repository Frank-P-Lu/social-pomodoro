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

          # Set completion message if room is already in break
          completion_msg =
            if room_state.status == :break do
              completion_message(room_state.duration_minutes, length(room_state.participants))
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
  def handle_event("set_status_message", %{"text" => text}, socket) do
    SocialPomodoro.Room.set_status_message(
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
  # TODO: major refactor needed. Most of these are not necessary. Only tick is necessary?
  def handle_info({:room_state, room_state}, socket) do
    # Update spectator status
    is_spectator = is_spectator?(room_state, socket.assigns.user_id)

    # Update completion message if in break (recompute in case participants changed)
    completion_msg =
      if room_state.status == :break do
        completion_message(room_state.duration_minutes, length(room_state.participants))
      else
        nil
      end

    # Find current participant
    current_participant =
      Enum.find(room_state.participants, &(&1.user_id == socket.assigns.user_id))

    socket =
      socket
      |> assign(:room_state, room_state)
      |> assign(:is_spectator, is_spectator)
      |> assign(:completion_message, completion_msg)
      |> assign(:current_participant, current_participant)
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
            <.active_session_view
              room_state={@room_state}
              user_id={@user_id}
              current_participant={@current_participant}
            />
          <% end %>

          <%= if @room_state.status == :break do %>
            <.break_view
              room_state={@room_state}
              user_id={@user_id}
              completion_message={@completion_message}
              current_participant={@current_participant}
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

  defp active_session_view(assigns) do
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
          
    <!-- Participants with status and status_message -->
          <div class="flex flex-wrap justify-center gap-6 mb-8">
            <%= for participant <- sort_participants_current_user_first(@room_state.participants, @user_id) do %>
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
          <%= if @current_participant && is_nil(@current_participant.status_message) do %>
            <div class="mb-8">
              <form phx-submit="set_status_message" class="flex gap-2 justify-center">
                <input
                  type="text"
                  name="text"
                  placeholder="What are you working on?"
                  class="input input-bordered w-full max-w-md text-base"
                  maxlength="30"
                  required
                />
                <button
                  type="submit"
                  phx-hook="MaintainWakeLock"
                  id="submit-status-message"
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
          {@completion_message}
        </p>

        <.timer_display
          id="break-timer-display"
          seconds_remaining={@room_state.seconds_remaining}
          label="Break time remaining"
        />
        
    <!-- Participants with ready status and status -->
        <div class="flex flex-wrap justify-center gap-6 mb-8">
          <%= for participant <- sort_participants_current_user_first(@room_state.participants, @user_id) do %>
            <.participant_display
              participant={participant}
              current_user_id={@user_id}
              show_ready={true}
            />
          <% end %>
        </div>
        
    <!-- Break Feedback Emoji Buttons -->
        <p class="text-sm opacity-70 mb-2">How are you feeling?</p>
        <div class="join mb-8 mx-auto">
          <button
            phx-click="set_status"
            phx-value-emoji="1F635-200D-1F4AB"
            phx-hook="MaintainWakeLock"
            id="break-emoji-1F635-200D-1F4AB"
            class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F635-200D-1F4AB", do: "btn-active"}"}
          >
            <img
              src="/images/emojis/1F635-200D-1F4AB.svg"
              class="w-8 h-8 md:w-12 md:h-12"
              alt="😵‍💫"
            />
          </button>
          <button
            phx-click="set_status"
            phx-value-emoji="1F62E-200D-1F4A8"
            phx-hook="MaintainWakeLock"
            id="break-emoji-1F62E-200D-1F4A8"
            class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F62E-200D-1F4A8", do: "btn-active"}"}
          >
            <img
              src="/images/emojis/1F62E-200D-1F4A8.svg"
              class="w-8 h-8 md:w-12 md:h-12"
              alt="😮‍💨"
            />
          </button>
          <button
            phx-click="set_status"
            phx-value-emoji="1F60C"
            phx-hook="MaintainWakeLock"
            id="break-emoji-1F60C"
            class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F60C", do: "btn-active"}"}
          >
            <img src="/images/emojis/1F60C.svg" class="w-8 h-8 md:w-12 md:h-12" alt="😌" />
          </button>
          <button
            phx-click="set_status"
            phx-value-emoji="2615"
            phx-hook="MaintainWakeLock"
            id="break-emoji-2615"
            class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "2615", do: "btn-active"}"}
          >
            <img src="/images/emojis/2615.svg" class="w-8 h-8 md:w-12 md:h-12" alt="☕" />
          </button>
          <button
            phx-click="set_status"
            phx-value-emoji="1F4AA"
            phx-hook="MaintainWakeLock"
            id="break-emoji-1F4AA"
            class={"join-item btn btn-neutral btn-square btn-lg #{if @current_participant.status_emoji == "1F4AA", do: "btn-active"}"}
          >
            <img src="/images/emojis/1F4AA.svg" class="w-8 h-8 md:w-12 md:h-12" alt="💪" />
          </button>
        </div>
        
    <!-- What was your session? -->
        <%= if @current_participant && is_nil(@current_participant.status_message) do %>
          <div class="mb-8">
            <form phx-submit="set_status_message" class="flex gap-2 justify-center">
              <input
                type="text"
                name="text"
                placeholder="How was your session?"
                class="input input-bordered w-full max-w-md text-base"
                maxlength="30"
                required
              />
              <button
                type="submit"
                id="submit-session-feedback"
                class="btn btn-square btn-primary"
              >
                <Icons.submit class="w-6 h-6 fill-current" />
              </button>
            </form>
          </div>
        <% end %>

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

        "You focused with #{if other_count == 1, do: "someone else", else: "#{other_count} other people"} for #{duration_minutes} minutes!"
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

  defp sort_participants_current_user_first(participants, current_user_id) do
    Enum.sort_by(participants, fn p ->
      if p.user_id == current_user_id, do: 0, else: 1
    end)
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
      <%= if @participant.status_message do %>
        <p class="text-xs opacity-70 text-center break-words w-full">
          {@participant.status_message}
        </p>
      <% end %>
      <%= if @show_ready && @participant.ready_for_next do %>
        <p class="text-xs text-success font-semibold">Ready!</p>
      <% end %>
    </div>
    """
  end
end
