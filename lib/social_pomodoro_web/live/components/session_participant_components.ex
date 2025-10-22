defmodule SocialPomodoroWeb.SessionParticipantComponents do
  use SocialPomodoroWeb, :html

  alias SocialPomodoroWeb.Icons
  alias SocialPomodoroWeb.SessionTabsComponents

  attr :participant, :map, required: true
  attr :is_break, :boolean, default: false

  def participant_display(assigns) do
    ~H"""
    <div
      class="participant-card card bg-primary/10 shadow-lg relative flex flex-col"
      phx-hook="ParticipantCard"
      id={"participant-card-#{@participant.user_id}"}
      data-participant-id={@participant.user_id}
    >
      <button
        class="absolute -top-2 -right-2 btn btn-neutral btn-sm btn-circle collapse-toggle z-50"
        data-action="toggle"
      >
        <Icons.chevron_left class="w-5 h-5 fill-current transition-transform duration-200 rotate-on-collapse" />
      </button>

      <div class="card p-2 flex flex-row items-center justify-center w-full ">
        <%!-- Avatar + username --%>
        <div class="flex flex-col items-center gap-1 flex-shrink-0 p-1 pr-2">
          <div class="relative flex items-center justify-center flex-shrink-0">
            <div class={if @is_break, do: "indicator", else: ""}>
              <%= if @is_break && @participant.ready_for_next do %>
                <span class="indicator-item indicator-start indicator-top badge badge-success badge-xs md:badge-sm">
                  ✓
                </span>
              <% end %>
              <.avatar
                user_id={@participant.user_id}
                username={@participant.username}
                size="w-10 md:w-14"
              />
            </div>
            <%= if @participant.status_emoji do %>
              <span class="absolute -bottom-1 -right-1 bg-base-100 rounded-full w-5 h-5 md:w-7 md:h-7 flex items-center justify-center border-2 border-base-100">
                <img
                  src={emoji_to_openmoji(@participant.status_emoji)}
                  class="w-5 h-5 md:w-7 md:h-7"
                  alt={@participant.status_emoji}
                />
              </span>
            <% end %>
          </div>
          <p class="font-semibold text-center text-xs leading-tight flex-shrink-0 truncate">
            {@participant.username}
          </p>
          <%= if @is_break && @participant.ready_for_next do %>
            <p class="text-xs text-success font-semibold">Skip</p>
          <% end %>

          <%!-- Preview section --%>
          <div class="content-short flex-row gap-2 items-center mt-1">
            <%!-- Task count --%>
            <% completed_count =
              if @participant.todos, do: Enum.count(@participant.todos, & &1.completed), else: 0 %>
            <% total_count = if @participant.todos, do: length(@participant.todos), else: 0 %>
            <div class="flex items-center gap-1">
              <Icons.todo class="w-3 h-3 fill-base-content/70" />
              <span class="text-[10px] text-base-content/70">{completed_count}/{total_count}</span>
            </div>

            <%!-- Chat indicator (only during breaks when they have messages) --%>
            <%= if @is_break && @participant.chat_messages && length(@participant.chat_messages) > 0 do %>
              <div class="flex items-center gap-1">
                <Icons.chat class="w-3 h-3 fill-secondary" />
                <span class="text-[10px] text-secondary">{length(@participant.chat_messages)}</span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Shouts section (next to avatar) --%>
        <%= if @is_break && @participant.chat_messages && length(@participant.chat_messages) > 0 do %>
          <div class="min-w-0 flex-1 content-full self-center max-h-24 overflow-y-auto pl-4">
            <.comment_bubble class="w-full">
              <:body>
                <div class="space-y-1.5 text-xs leading-snug break-words">
                  <%= for message <- @participant.chat_messages do %>
                    <div>{message.text}</div>
                  <% end %>
                </div>
              </:body>
            </.comment_bubble>
          </div>
        <% end %>
      </div>

      <div class="bg-base-100 rounded-lg flex flex-col gap-2 p-2 md:p-4 content-full min-h-0">
        <div class="min-w-0 flex flex-col items-center flex-1 min-h-0">
          <h4 class="text-xs font-semibold uppercase tracking-wide opacity-70 mb-1 flex-shrink-0">
            Tasks
          </h4>
          <%= if @participant.todos && length(@participant.todos) > 0 do %>
            <div class="space-y-1 flex-1 overflow-y-auto min-h-0 w-full">
              <%= for todo <- @participant.todos do %>
                <div class="flex items-center gap-1">
                  <input
                    type="checkbox"
                    checked={todo.completed}
                    disabled
                    class="checkbox checkbox-xs checkbox-primary"
                  />
                  <span class={[
                    "text-xs md:text-sm",
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
      </div>
    </div>
    """
  end

  attr :participant, :map, required: true
  attr :is_break, :boolean, default: false

  def current_user_avatar_with_status(assigns) do
    ~H"""
    <div class="flex flex-col items-center flex-shrink-0">
      <div class="relative">
        <.avatar
          user_id={@participant.user_id}
          username={@participant.username}
          size="w-11 xs:w-12 md:w-16"
          class="ring-primary ring-offset-base-100 rounded-full shadow-md ring-1 xs:ring-2 md:ring-4 ring-offset-1 md:ring-offset-2"
        />
        <%= if @participant.status_emoji do %>
          <span class="absolute -bottom-1 -right-1 md:-bottom-2 md:-right-2 bg-base-100 rounded-full w-6 h-6 xs:w-7 xs:h-7 md:w-10 md:h-10 flex items-center justify-center shadow-lg">
            <img
              src={emoji_to_openmoji(@participant.status_emoji)}
              class="w-5 h-5 xs:w-6 xs:h-6 md:w-9 md:h-9"
              alt={@participant.status_emoji}
            />
          </span>
        <% end %>
      </div>

      <p class="font-bold text-center mt-1 xs:mt-2 text-sm xs:text-base md:text-lg">
        {@participant.username}
      </p>
      <%= if @is_break && @participant.ready_for_next do %>
        <p class="text-xs text-success font-semibold mt-1">Skip</p>
      <% end %>
    </div>
    """
  end

  attr :current_participant, :map, required: true
  attr :status_emojis, :list, required: true
  attr :id_prefix, :string, default: ""

  def status_emoji_selector(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 flex-shrink-0 md:mb-2 md:ml-4">
      <div class="join">
        <%= for emoji <- @status_emojis do %>
          <button
            phx-click="set_status"
            phx-value-emoji={emoji.code}
            phx-hook="MaintainWakeLock"
            id={"#{@id_prefix}emoji-#{emoji.code}"}
            class={[
              "btn btn-square join-item border btn-sm xs:btn-md transition-colors duration-150 bg-base-100 border-transparent hover:bg-base-200 hover:border-base-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-base-300 focus-visible:ring-offset-2 focus-visible:ring-offset-base-200",
              @current_participant.status_emoji == emoji.code &&
                "bg-base-200 border-base-300 text-base-content shadow-sm",
              @current_participant.status_emoji != emoji.code && "text-base-content/80"
            ]}
            aria-pressed={@current_participant.status_emoji == emoji.code}
          >
            <img src={emoji.path} class="w-6 h-6 xs:w-7 xs:h-7" alt={emoji.alt} />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :current_participant, :map, required: true
  attr :status_emojis, :list, required: true
  attr :room_state, :map, required: true
  attr :selected_tab, :atom, required: true
  attr :placeholder, :string, default: "What are you working on?"
  attr :is_break, :boolean, default: false
  attr :emoji_id_prefix, :string, default: ""
  attr :completed_count, :integer, required: true
  attr :total_count, :integer, required: true
  attr :user_id, :string, required: true

  def current_user_card(assigns) do
    ~H"""
    <div class="flex flex-col w-full h-full relative">
      <div class="w-full h-full flex flex-col">
        <div class="card bg-base-300 px-4 pb-4 pt-2 flex-grow flex flex-col md:py-6">
          <div class="flex-grow">
            <SessionTabsComponents.tabs_with_content
              room_state={@room_state}
              selected_tab={@selected_tab}
              current_participant={@current_participant}
              placeholder={@placeholder}
              user_id={@user_id}
            >
              <:avatar_card>
                <div class="card bg-gray-700 shadow-lg p-2 pt-3 xs:p-3 xs:pt-4 md:p-3 md:pt-5">
                  <.current_user_avatar_with_status
                    participant={@current_participant}
                    is_break={@is_break}
                  />
                </div>
              </:avatar_card>
              <:left_controls>
                <.status_emoji_selector
                  current_participant={@current_participant}
                  status_emojis={@status_emojis}
                  id_prefix={@emoji_id_prefix}
                />
              </:left_controls>
            </SessionTabsComponents.tabs_with_content>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :other_participants, :list, required: true
  attr :is_break, :boolean, default: false

  def other_participants_section(assigns) do
    ~H"""
    <%= if length(@other_participants) > 0 do %>
      <div class="divider">
        <div class="flex items-center gap-2">
          <Icons.users class="w-4 h-4 fill-current opacity-70" />
          <span>Other Participants ({length(@other_participants)})</span>
        </div>
      </div>
      <div class="flex flex-col items-center gap-4 mb-4">
        <div :for={participant <- @other_participants} :key={participant.user_id}>
          <.participant_display
            participant={participant}
            is_break={@is_break}
          />
        </div>
      </div>
    <% end %>
    """
  end

  defp emoji_to_openmoji(unicode_code) do
    "/images/emojis/#{unicode_code}.svg"
  end
end
