defmodule SocialPomodoroWeb.SessionLive do
  use SocialPomodoroWeb, :live_view

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
        end

        # Get initial room state
        {:ok, pid} = SocialPomodoro.RoomRegistry.get_room(name)
        room_state = SocialPomodoro.Room.get_state(pid)

        # Check if user is already in the room, if not, try to join
        user_in_room = Enum.any?(room_state.participants, &(&1.user_id == user_id))

        if user_in_room do
          # User is already in the room, let them in
          socket =
            socket
            |> assign(:name, name)
            |> assign(:room_state, room_state)
            |> assign(:user_id, user_id)
            |> assign(:username, username)
            |> assign(:selected_emoji, nil)
            |> assign(:redirect_countdown, nil)

          {:ok, socket}
        else
          # User not in room, show redirect screen
          Process.send_after(self(), :countdown, 1000)

          socket =
            socket
            |> assign(:name, name)
            |> assign(:room_state, room_state)
            |> assign(:user_id, user_id)
            |> assign(:username, username)
            |> assign(:selected_emoji, nil)
            |> assign(:redirect_countdown, 5)

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
  def handle_event("send_reaction", %{"emoji" => emoji}, socket) do
    SocialPomodoro.Room.add_reaction(
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
    {:noreply, assign(socket, :room_state, room_state)}
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
  def handle_info(:countdown, socket) do
    case socket.assigns.redirect_countdown do
      1 ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      n ->
        Process.send_after(self(), :countdown, 1000)
        {:noreply, assign(socket, :redirect_countdown, n - 1)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 flex items-center justify-center p-8">
      <div class="max-w-4xl w-full">
        <%= if @redirect_countdown do %>
          <.redirect_view countdown={@redirect_countdown} />
        <% else %>
          <%= if @room_state.status == :waiting do %>
            <.waiting_view room_state={@room_state} user_id={@user_id} />
          <% end %>

          <%= if @room_state.status == :active do %>
            <.active_session_view room_state={@room_state} />
          <% end %>

          <%= if @room_state.status == :break do %>
            <.break_view room_state={@room_state} user_id={@user_id} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp waiting_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body text-center">
        <h1 class="card-title text-3xl justify-center mb-8">Waiting to Start</h1>
        
    <!-- Participants -->
        <div class="flex justify-center gap-4 mb-8">
          <%= for participant <- @room_state.participants do %>
            <div class="text-center">
              <div class="avatar">
                <div class="w-16 rounded-full">
                  <img
                    src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
                    alt={participant.username}
                  />
                </div>
              </div>
              <p class="text-sm mt-2">{participant.username}</p>
            </div>
          <% end %>
        </div>

        <p class="text-lg mb-8">
          {length(@room_state.participants)} {if length(@room_state.participants) == 1,
            do: "person",
            else: "people"} in room
          · {@room_state.duration_minutes} minute session
        </p>

        <div class="card-actions justify-center">
          <%= if @room_state.creator == @user_id do %>
            <button
              phx-click="start_session"
              class="btn btn-primary btn-lg"
            >
              Start Session
            </button>
          <% else %>
            <p class="opacity-50">Waiting for {@room_state.creator_username} to start...</p>
          <% end %>
        </div>

        <button phx-click="leave_room" class="link link-hover mt-4">
          Leave Room
        </button>
      </div>
    </div>
    """
  end

  defp active_session_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body text-center">
        <!-- Timer Display -->
        <div
          id="timer-display"
          class="text-5xl font-bold text-primary mb-2"
          phx-hook="Timer"
          data-seconds-remaining={@room_state.seconds_remaining}
        >
          {format_time(@room_state.seconds_remaining)}
        </div>
        <p class="text-xl mb-8">Focus time remaining</p>
        
    <!-- Participants -->
        <div class="avatar-group -space-x-6 justify-center mb-8">
          <%= for participant <- @room_state.participants do %>
            <div class="avatar">
              <div class="w-12">
                <img
                  src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
                  alt={participant.username}
                />
              </div>
            </div>
          <% end %>
        </div>
        
    <!-- Reaction Buttons -->
        <div class="join mb-8">
          <button
            phx-click="send_reaction"
            phx-value-emoji="🔥"
            class="join-item btn btn-lg text-4xl"
          >
            🔥
          </button>
          <button
            phx-click="send_reaction"
            phx-value-emoji="💪"
            class="join-item btn btn-lg text-4xl"
          >
            💪
          </button>
          <button
            phx-click="send_reaction"
            phx-value-emoji="⚡"
            class="join-item btn btn-lg text-4xl"
          >
            ⚡
          </button>
          <button
            phx-click="send_reaction"
            phx-value-emoji="🎯"
            class="join-item btn btn-lg text-4xl"
          >
            🎯
          </button>
        </div>
        
    <!-- Recent Reactions -->
        <%= if !Enum.empty?(@room_state.reactions) do %>
          <div class="bg-base-300 rounded-lg p-4 max-h-32 overflow-y-auto">
            <div class="flex flex-wrap gap-2 justify-center">
              <%= for reaction <- Enum.take(@room_state.reactions, 20) do %>
                <div class="badge badge-lg gap-1">
                  <span>{reaction.emoji}</span>
                  <span>{reaction.username}</span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <button phx-click="leave_room" class="link link-hover text-sm mt-6">
          Leave Session
        </button>
      </div>
    </div>
    """
  end

  defp break_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body text-center">
        <div class="text-6xl mb-6">🎉</div>
        <h1 class="card-title text-4xl justify-center mb-4">Great Work!</h1>
        <p class="text-xl mb-8">
          {completion_message(@room_state.duration_minutes, length(@room_state.participants))}
        </p>

        <div
          id="break-timer-display"
          class="text-5xl font-bold text-primary mb-2"
          phx-hook="Timer"
          data-seconds-remaining={@room_state.seconds_remaining}
        >
          {format_time(@room_state.seconds_remaining)}
        </div>
        <p class="text-lg opacity-70 mb-12">Break time remaining</p>
        
    <!-- Participants with ready status -->
        <div class="flex justify-center gap-4 mb-8">
          <%= for participant <- @room_state.participants do %>
            <div class="text-center">
              <div class="indicator">
                <%= if participant.ready_for_next do %>
                  <span class="indicator-item badge badge-success badge-sm">✓</span>
                <% end %>
                <div class="avatar">
                  <div class="w-16 rounded-full">
                    <img
                      src={"https://api.dicebear.com/9.x/thumbs/svg?seed=#{participant.user_id}"}
                      alt={participant.username}
                    />
                  </div>
                </div>
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
            class="btn btn-lg"
          >
            Return to Lobby
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

  defp redirect_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body text-center">
        <div class="text-6xl mb-6">👋</div>
        <h1 class="card-title text-3xl justify-center mb-4">Oops! You're not in this room</h1>
        <p class="text-xl mb-8">
          This session is only for participants who joined from the lobby.
        </p>
        <p class="text-lg mb-8">
          Heading back to the lobby in <span class="font-bold text-primary">{@countdown}</span>
          {if @countdown == 1, do: "second", else: "seconds"}...
        </p>
        <div class="card-actions justify-center">
          <a
            href="/"
            class="btn btn-primary btn-lg"
          >
            Go to Lobby Now
          </a>
        </div>
      </div>
    </div>
    """
  end
end
