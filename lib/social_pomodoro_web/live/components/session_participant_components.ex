defmodule SocialPomodoroWeb.SessionParticipantComponents do
  use SocialPomodoroWeb, :html

  alias SocialPomodoroWeb.Icons
  alias SocialPomodoroWeb.SessionTabsComponents

  attr :participant, :map, required: true
  attr :show_ready, :boolean, default: false
  attr :current_user_id, :string, default: nil
  attr :chat_messages, :map, default: %{}

  def participant_display(assigns) do
    user_messages =
      assigns.chat_messages
      |> Map.get(assigns.participant.user_id, [])
      |> Enum.take(3)

    assigns = Map.put(assigns, :user_messages, user_messages)

    ~H"""
    <div
      class="card bg-base-300 shadow-lg max-w-sm relative p-4"
      phx-hook="ParticipantCard"
      id={"participant-card-#{@participant.user_id}"}
      data-participant-id={@participant.user_id}
    >
      <div class="flex gap-4">
        <button
          class="absolute top-2 right-2 btn btn-ghost btn-sm btn-circle collapse-toggle z-10"
          data-action="toggle"
        >
          <Icons.chevron_left class="w-5 h-5 fill-current transition-transform duration-200 chevron-icon" />
        </button>

        <div class="flex flex-col items-center gap-2 flex-shrink-0 w-20">
          <div class="relative">
            <div class={if @show_ready, do: "indicator", else: ""}>
              <%= if @show_ready && @participant.ready_for_next do %>
                <span class="indicator-item badge badge-success badge-sm">✓</span>
              <% end %>
              <.avatar
                user_id={@participant.user_id}
                username={@participant.username}
                size="w-14"
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
              <span class="absolute -bottom-1 -right-1 bg-base-100 rounded-full w-7 h-7 flex items-center justify-center border-2 border-base-100">
                <img
                  src={emoji_to_openmoji(@participant.status_emoji)}
                  class="w-7 h-7"
                  alt={@participant.status_emoji}
                />
              </span>
            <% end %>
          </div>
          <p class="font-semibold text-center text-xs leading-tight">{@participant.username}</p>
          <%= if @show_ready && @participant.ready_for_next do %>
            <p class="text-xs text-success font-semibold">Ready!</p>
          <% end %>
        </div>

        <div class="flex-grow overflow-hidden collapsible-content">
          <div class="mb-2">
            <h4 class="text-xs font-semibold uppercase tracking-wide opacity-70 mb-1">Tasks</h4>
            <%= if @participant.todos && length(@participant.todos) > 0 do %>
              <div class="space-y-1">
                <%= for todo <- @participant.todos do %>
                  <div class="flex items-center gap-1">
                    <input
                      type="checkbox"
                      checked={todo.completed}
                      disabled
                      class="checkbox checkbox-xs"
                    />
                    <span class={[
                      "text-xs",
                      if(todo.completed, do: "line-through opacity-50", else: nil)
                    ]}>
                      {todo.text}
                    </span>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="text-xs opacity-50">No tasks yet</p>
            <% end %>
          </div>

          <%= if @show_ready && length(@user_messages) > 0 do %>
            <div class="divider my-1"></div>
            <div>
              <h4 class="text-xs font-semibold uppercase tracking-wide opacity-70 mb-1">
                Recent Messages
              </h4>
              <div class="space-y-1">
                <%= for message <- @user_messages do %>
                  <div class="chat chat-start">
                    <div class="chat-bubble chat-bubble-secondary text-xs py-1 px-2 min-h-0">
                      {message.text}
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :participant, :map, required: true
  attr :show_ready, :boolean, default: false

  def current_user_avatar_with_status(assigns) do
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

  def status_emoji_selector(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 flex-shrink-0">
      <div class="grid grid-cols-3 gap-2">
        <%= for emoji <- @status_emojis do %>
          <button
            phx-click="set_status"
            phx-value-emoji={emoji.code}
            phx-hook="MaintainWakeLock"
            id={"#{@id_prefix}emoji-#{emoji.code}"}
            class={[
              "btn btn-neutral btn-square btn-lg",
              if(@current_participant.status_emoji == emoji.code, do: "btn-active", else: nil)
            ]}
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

  def horizontal_session_layout(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center gap-4 mb-8 w-full">
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

      <div class="w-full">
        <SessionTabsComponents.tabs_with_content
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
  attr :chat_messages, :map, default: %{}
  attr :current_user_id, :string, default: nil

  def other_participants_section(assigns) do
    ~H"""
    <%= if length(@other_participants) > 0 do %>
      <div class="divider">Other Participants</div>
      <div class="flex flex-col items-center gap-4 mb-4">
        <%= for participant <- @other_participants do %>
          <.participant_display
            participant={participant}
            show_ready={@show_ready}
            chat_messages={@chat_messages}
            current_user_id={@current_user_id}
          />
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :user_id, :string, required: true
  attr :username, :string, required: true
  attr :current_user_id, :string, required: true
  attr :size, :string, default: "w-16"

  def participant_avatar(assigns) do
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

  defp emoji_to_openmoji(unicode_code) do
    "/images/emojis/#{unicode_code}.svg"
  end
end
