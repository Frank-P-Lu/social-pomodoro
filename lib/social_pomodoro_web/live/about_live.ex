defmodule SocialPomodoroWeb.AboutLive do
  use SocialPomodoroWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center p-4">
      <div class="max-w-2xl w-full space-y-8">
        <div class="text-center">
          <h1 class="text-4xl font-bold mb-2">About</h1>
          <p class="text-lg opacity-70">Focus with strangers</p>
        </div>

        <div class="card bg-base-200 shadow-xl">
          <div class="card-body space-y-6">
            <div class="flex justify-center">
              <div class="badge badge-secondary badge-outline gap-2 border-dashed">
                <img src="/images/emojis/1F389.svg" alt="party popper" class="w-4 h-4" />
                Yay! You made it!
              </div>
            </div>

            <section>
              <h2 class="text-2xl font-semibold mb-3">What is this?</h2>
              <p class="leading-relaxed">
                I built this as a collaborative pomodoro timer where you can work alongside others in real-time.
                You can create or join rooms, sync your focus sessions, take breaks together, and
                stay motivated with shared goals.
              </p>
            </section>

            <div class="divider"></div>

            <section>
              <h2 class="text-2xl font-semibold mb-3">Credits</h2>
              <div class="space-y-4">
                <div>
                  <h3 class="font-semibold mb-1">Emojis</h3>
                  <p class="text-sm opacity-80">
                    All emojis designed by
                    <a
                      href="https://openmoji.org/"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="link link-primary"
                    >
                      OpenMoji
                    </a>
                    – the open-source emoji and icon project. License:
                    <a
                      href="https://creativecommons.org/licenses/by-sa/4.0/"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="link link-primary"
                    >
                      CC BY-SA 4.0
                    </a>
                  </p>
                </div>

                <div>
                  <h3 class="font-semibold mb-1">Sound Effects</h3>
                  <p class="text-sm opacity-80">
                    Sound effects from
                    <a
                      href="https://pixabay.com/users/aldermanswe-21004879/"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="link link-primary"
                    >
                      aldermanswe
                    </a>
                    and
                    <a
                      href="https://pixabay.com/users/themediaguy-50389411/"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="link link-primary"
                    >
                      themediaguy
                    </a>
                    on Pixabay
                  </p>
                </div>
              </div>
            </section>

            <div class="divider"></div>

            <section>
              <h2 class="text-2xl font-semibold mb-3">Privacy</h2>
              <p class="leading-relaxed text-sm opacity-80">
                No accounts required. Your username is stored locally in your browser.
                Room data is temporary and deleted when sessions end.
              </p>
            </section>

            <div class="divider"></div>

            <section>
              <p class="text-sm opacity-80 text-center">
                If you need anything, email me at
                <a href="mailto:frank@focuswithstrangers.com" class="link link-primary">
                  frank@focuswithstrangers.com
                </a>
              </p>
            </section>
          </div>
        </div>

        <div class="text-center">
          <.link navigate="/" class="btn btn-primary">
            Back to Lobby
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
