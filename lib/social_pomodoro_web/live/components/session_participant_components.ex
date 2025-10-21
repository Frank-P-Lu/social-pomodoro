defmodule SocialPomodoroWeb.SessionParticipantComponents do
  use SocialPomodoroWeb, :html

  alias SocialPomodoroWeb.Icons
  alias SocialPomodoroWeb.SessionTabsComponents

  attr :participant, :map, required: true
  attr :show_ready, :boolean, default: false

  def participant_display(assigns) do
    ~H"""
    <div
      class="card bg-base-300 shadow-lg relative p-4"
      phx-hook="ParticipantCard"
      id={"participant-card-#{@participant.user_id}"}
      data-participant-id={@participant.user_id}
    >
      <div class="flex gap-4 items-start">
        <button
          class="absolute -top-2 -right-2 btn btn-neutral btn-sm btn-circle collapse-toggle z-10"
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

        <div class="flex-grow overflow-hidden flex gap-4 collapsible-content">
          <%= if @show_ready && @participant.chat_messages && length(@participant.chat_messages) > 0 do %>
            <div class="flex-shrink-0 min-w-0">
              <h4 class="text-xs font-semibold uppercase tracking-wide opacity-70 mb-1">
                Shouts
              </h4>
              <div class="space-y-1">
                <%= for message <- @participant.chat_messages do %>
                  <div class="chat chat-start">
                    <div class="chat-bubble chat-bubble-secondary text-xs py-1 px-2 min-h-0">
                      {message.text}
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <div class="divider divider-horizontal mx-0"></div>
          <% end %>

          <div class="flex-grow min-w-0">
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
        </div>
      </div>
    </div>
    """
  end

  attr :participant, :map, required: true
  attr :show_ready, :boolean, default: false

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
      <%= if @show_ready && @participant.ready_for_next do %>
        <p class="text-xs text-success font-semibold mt-1">Ready!</p>
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
              "btn btn-square join-item border transition-colors duration-200 btn-sm xs:btn-md",
              @current_participant.status_emoji == emoji.code &&
                "bg-base-300 border-base-300 text-base-content",
              @current_participant.status_emoji != emoji.code &&
                "bg-base-100 border-base-200 hover:bg-base-200 hover:border-base-300"
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
  attr :show_ready, :boolean, default: false
  attr :emoji_id_prefix, :string, default: ""
  attr :completed_count, :integer, required: true
  attr :total_count, :integer, required: true
  attr :user_id, :string, required: true

  def current_user_card(assigns) do
    ~H"""
    <div class="flex flex-col w-full h-full relative">
      <div class="w-full h-full flex flex-col">
        <div class="card bg-base-300 px-4 pb-4 pt-2 flex-grow flex flex-col md:p-4">
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
                    show_ready={@show_ready}
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
  attr :show_ready, :boolean, default: false

  def other_participants_section(assigns) do
    ~H"""
    <%= if length(@other_participants) > 0 do %>
      <div class="divider">Other Participants</div>
      <div class="flex flex-col items-center gap-4 mb-4">
        <div :for={participant <- @other_participants} :key={participant.user_id}>
          <.participant_display
            participant={participant}
            show_ready={@show_ready}
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
