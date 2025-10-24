// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Wake Lock functionality
let wakeLock = null

async function ensureWakeLock() {
  if (!('wakeLock' in navigator)) {
    return // Wake Lock API not supported
  }

  if (!wakeLock || wakeLock.released) {
    try {
      wakeLock = await navigator.wakeLock.request('screen')
    } catch (err) {
      // Fail silently - might fail if page not visible or permission denied
    }
  }
}

// Audio context for alert sounds
let alertAudio = null

function initializeAudio() {
  if (!alertAudio) {
    alertAudio = new Audio('/sounds/alert.wav')
    // Load the audio file during user interaction to unlock it in Safari
    alertAudio.load()
  }
}

function releaseWakeLock() {
  if (wakeLock && !wakeLock.released) {
    wakeLock.release()
    wakeLock = null
  }
}

// Re-acquire wake lock when page becomes visible again
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && wakeLock && wakeLock.released) {
    ensureWakeLock()
  }
})

let Hooks = {}

Hooks.CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault()
      const roomName = this.el.dataset.roomName
      const url = `${window.location.origin}/at/${roomName}`

      navigator.clipboard.writeText(url).then(() => {
        this.pushEvent("link_copied", {})
      }).catch(err => {
        console.error("Failed to copy:", err)
      })
    })
  }
}

const APP_TITLE = 'focus with strangers'

Hooks.Timer = {
  mounted() {
    this.seconds = parseInt(this.el.dataset.secondsRemaining, 10)
    this.isBreak = this.el.id === 'break-timer-display'
    this.segmentTargets = this.getSegmentTargets()
    this.applyAnimationSetting()
    this.updateTimer()
    this.interval = setInterval(() => {
      this.seconds--
      if (this.seconds >= 0) {
        this.updateTimer()
      }
      if (this.seconds === 0) {
        // Play alert sound only when transitioning from active session (not from break)
        if (alertAudio && !this.isBreak) {
          alertAudio.currentTime = 0
          alertAudio.play().catch(err => console.error('Failed to play alert:', err))
        }
      }
    }, 1000)
  },
  updated() {
    // Reset timer on update from server
    this.seconds = parseInt(this.el.dataset.secondsRemaining, 10)
    this.isBreak = this.el.id === 'break-timer-display'
    this.segmentTargets = this.getSegmentTargets()
    this.applyAnimationSetting()
    this.updateTimer()
  },
  applyAnimationSetting() {
    const isAnimated = getSavedTimerAnimation() === 'true'
    // Find the timer display spans (they have font-mono and text-5xl)
    const timerSpans = this.el.querySelectorAll('.font-mono.text-5xl')
    timerSpans.forEach(el => {
      if (isAnimated) {
        el.classList.add('countdown')
      } else {
        el.classList.remove('countdown')
      }
    })
  },
  destroyed() {
    clearInterval(this.interval)
    // Reset title when leaving the page
    document.title = APP_TITLE
  },
  getSegmentTargets() {
    const segments = {}
      ;['minutes', 'seconds'].forEach((unit) => {
        const valueEl = this.el.querySelector(`[data-countdown-segment="${unit}"] [data-countdown-value]`)
        if (valueEl) {
          segments[unit] = valueEl
        }
      })
    return segments
  },
  updateSegment(unit, value) {
    const target = this.segmentTargets?.[unit]
    if (!target) return

    const safeValue = Math.max(0, Math.floor(value))
    target.style.setProperty('--value', safeValue)
    target.textContent = `${safeValue}`
    target.setAttribute('aria-label', `${safeValue}`)
  },
  breakdown(seconds) {
    const safeSeconds = Math.max(0, seconds)
    const minutes = Math.floor(safeSeconds / 60)
    const secs = safeSeconds % 60

    return { minutes, seconds: secs }
  },
  updateTimer() {
    const { minutes, seconds } = this.breakdown(this.seconds)

    this.updateSegment('minutes', minutes)
    this.updateSegment('seconds', seconds)

    const displayMinutes = Math.floor(this.seconds / 60)
    const displaySeconds = this.seconds % 60
    const timeStr = `${displayMinutes}:${displaySeconds.toString().padStart(2, '0')}`

    // Update tab title
    if (this.isBreak) {
      document.title = `BREAK ${timeStr} | ${APP_TITLE}`
    } else {
      document.title = `${timeStr} | ${APP_TITLE}`
    }
  }
}

Hooks.AutostartTimer = {
  mounted() {
    this.seconds = parseInt(this.el.dataset.secondsRemaining, 10)
    this.updateDisplay()
    this.interval = setInterval(() => {
      this.seconds--
      if (this.seconds >= 0) {
        this.updateDisplay()
      }
    }, 1000)
  },
  updated() {
    // Sync with server updates (every 10 seconds) but only if drift is significant
    const serverSeconds = parseInt(this.el.dataset.secondsRemaining, 10)
    const drift = Math.abs(this.seconds - serverSeconds)

    // Only resync if drift is more than 2 seconds (accounts for network latency)
    if (drift > 2) {
      this.seconds = serverSeconds
      this.updateDisplay()
    }
  },
  destroyed() {
    clearInterval(this.interval)
  },
  updateDisplay() {
    const minutes = Math.floor(this.seconds / 60)
    const secs = this.seconds % 60
    const timeStr = `${minutes}:${secs.toString().padStart(2, '0')}`
    this.el.textContent = timeStr
  }
}

Hooks.RequestWakeLock = {
  mounted() {
    ensureWakeLock()
    initializeAudio()
  }
}

Hooks.MaintainWakeLock = {
  mounted() {
    ensureWakeLock()
  },
  updated() {
    ensureWakeLock()
  }
}

Hooks.ReleaseWakeLock = {
  mounted() {
    this.el.addEventListener("click", () => {
      releaseWakeLock()
    })
  }
}

Hooks.ClearForm = {
  mounted() {
    this.handleEvent("clear-form", ({ id }) => {
      if (this.el.id === id) {
        this.el.reset()
      }
    })
  }
}

Hooks.ParticipantCard = {
  mounted() {
    this.storageKey = `participant-card-expanded-${this.el.dataset.participantId}`

    // Load saved state from sessionStorage (auto-clears when tab closes)
    // Default to expanded (true), unless explicitly set to collapsed (false)
    const isExpanded = sessionStorage.getItem(this.storageKey) !== 'false'
    this.el.dataset.expanded = String(isExpanded)

    // Add click handler for toggle button
    this.el.querySelector('.collapse-toggle').addEventListener('click', (e) => {
      e.preventDefault()
      const currentlyExpanded = this.el.dataset.expanded === 'true'
      this.el.dataset.expanded = String(!currentlyExpanded)
      sessionStorage.setItem(this.storageKey, String(!currentlyExpanded))
    })
  },
  updated() {
    // Restore the expanded state after LiveView patches the DOM
    const isExpanded = sessionStorage.getItem(this.storageKey) !== 'false'
    this.el.dataset.expanded = String(isExpanded)
  }
}

Hooks.ShoutMessage = {
  mounted() {
    // Trigger slide-in animation
    this.el.style.animation = 'slide-in 0.3s ease-out'
  },
  beforeDestroy() {
    // Prevent removal until animation completes
    const animationDuration = 300 // ms
    this.el.style.animation = 'slide-out 0.3s ease-out'

    // Delay the actual removal
    return new Promise(resolve => {
      setTimeout(resolve, animationDuration)
    })
  }
}

// Global audio controller (shared across lobby and session)
let globalAudio = null
let fadeInterval = null

// Sound file mappings
const SOUND_FILES = {
  'rain': '/sounds/fwc-rain.mp3',
  'cafe': '/sounds/fwc-cafe.mp3',
  'white_noise': '/sounds/fwc-white-noise.mp3'
}

// Helper functions for sessionStorage
function getSavedVolume() {
  return sessionStorage.getItem('ambient_volume') || '50'
}

function getSavedSound() {
  return sessionStorage.getItem('ambient_sound') || 'none'
}

function getSavedTimerAnimation() {
  // Default to 'true' (animated)
  const saved = sessionStorage.getItem('timer_animation')
  return saved === null ? 'true' : saved
}

function getGlobalAudio() {
  if (!globalAudio) {
    globalAudio = new Audio()
    globalAudio.loop = true

    // Set initial volume from sessionStorage
    globalAudio.volume = parseInt(getSavedVolume()) / 100
  }
  return globalAudio
}

function fadeOutAudio(duration = 2000) {
  const audio = getGlobalAudio()
  const targetVolume = parseInt(getSavedVolume()) / 100
  const startVolume = audio.volume
  const startTime = Date.now()

  // Clear any existing fade
  if (fadeInterval) {
    clearInterval(fadeInterval)
  }

  fadeInterval = setInterval(() => {
    const elapsed = Date.now() - startTime
    const progress = Math.min(elapsed / duration, 1)

    // Linear fade from current volume to 0
    audio.volume = startVolume * (1 - progress)

    if (progress >= 1) {
      clearInterval(fadeInterval)
      fadeInterval = null
      audio.pause()
      audio.currentTime = 0
      // Restore original volume for next playback
      audio.volume = targetVolume
    }
  }, 50)
}

Hooks.AudioSettings = {
  mounted() {
    // Get references to UI elements
    this.container = this.el
    this.backdrop = this.el.querySelector('[data-backdrop]')
    this.panel = this.el.querySelector('[data-panel]')
    this.closeBtn = this.el.querySelector('[data-close]')
    this.soundButtons = this.el.querySelectorAll('[data-sound]')
    this.volumeSlider = this.el.querySelector('[data-volume-slider]')
    this.timerAnimationToggle = this.el.querySelector('[data-timer-animation-toggle]')

    // Get mode (lobby or session)
    this.mode = this.el.dataset.mode || 'lobby'

    // Load saved preferences
    this.currentSound = getSavedSound()
    this.currentVolume = getSavedVolume()
    this.timerAnimationEnabled = getSavedTimerAnimation() === 'true'

    // Update UI to reflect saved state
    this.updateUI()

    // Setup event listeners
    this.setupListeners()

    // Track preview timeout
    this.previewTimeout = null
  },

  setupListeners() {
    // Open button (find it in the document)
    const openBtn = document.querySelector('[data-open-audio-settings]')
    if (openBtn) {
      openBtn.addEventListener('click', () => this.show())
    }

    // Close button
    this.closeBtn.addEventListener('click', () => this.hide())

    // Backdrop click
    this.backdrop.addEventListener('click', () => this.hide())

    // Sound selection buttons
    this.soundButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const sound = btn.dataset.sound
        this.selectSound(sound)
      })
    })

    // Volume slider
    this.volumeSlider.addEventListener('input', (e) => {
      this.changeVolume(e.target.value)
    })

    // Timer animation toggle (only in session mode)
    if (this.timerAnimationToggle) {
      this.timerAnimationToggle.addEventListener('change', (e) => {
        this.toggleTimerAnimation(e.target.checked)
      })
    }
  },

  updateUI() {
    // Update active sound button
    this.soundButtons.forEach(btn => {
      if (btn.dataset.sound === this.currentSound) {
        btn.classList.add('btn-primary')
        btn.classList.remove('btn-outline')
      } else {
        btn.classList.remove('btn-primary')
        btn.classList.add('btn-outline')
      }
    })

    // Update volume slider
    this.volumeSlider.value = this.currentVolume

    // Update timer animation toggle (only in session mode)
    if (this.timerAnimationToggle) {
      this.timerAnimationToggle.checked = this.timerAnimationEnabled
    }
  },

  toggleTimerAnimation(enabled) {
    this.timerAnimationEnabled = enabled
    sessionStorage.setItem('timer_animation', String(enabled))

    // Toggle the countdown class on all timer elements
    const countdownContainers = document.querySelectorAll('.countdown, .font-mono.text-5xl')
    countdownContainers.forEach(el => {
      if (enabled) {
        el.classList.add('countdown')
      } else {
        el.classList.remove('countdown')
      }
    })
  },

  selectSound(sound) {
    this.currentSound = sound
    sessionStorage.setItem('ambient_sound', sound)
    this.updateUI()

    // Clear any existing preview timeout
    if (this.previewTimeout) {
      clearTimeout(this.previewTimeout)
      this.previewTimeout = null
    }

    // Update global audio
    const audio = getGlobalAudio()

    if (sound === 'none') {
      fadeOutAudio(1000)
    } else {
      const soundFile = SOUND_FILES[sound]
      if (soundFile) {
        // Restore volume before playing
        audio.volume = parseInt(getSavedVolume()) / 100

        // Always update src and play, even if switching from 'none'
        if (audio.src !== window.location.origin + soundFile) {
          audio.src = soundFile
        }
        audio.play().catch(err => console.error('Failed to play audio:', err))

        // In lobby mode, fade out after 3 seconds (preview)
        if (this.mode === 'lobby') {
          this.previewTimeout = setTimeout(() => {
            fadeOutAudio(2000) // 2 second fade out
          }, 3000)
        }
        // In session mode, play continuously (no timeout)
      }
    }
  },

  changeVolume(volume) {
    this.currentVolume = volume
    sessionStorage.setItem('ambient_volume', volume)
    const audio = getGlobalAudio()
    audio.volume = parseInt(volume) / 100
  },

  show() {
    this.container.classList.remove('hidden')
    requestAnimationFrame(() => {
      this.backdrop.classList.remove('opacity-0')
      this.backdrop.classList.add('opacity-100')
      this.panel.classList.remove('translate-x-full')
      this.panel.classList.add('translate-x-0')
    })
  },

  hide() {
    this.backdrop.classList.remove('opacity-100')
    this.backdrop.classList.add('opacity-0')
    this.panel.classList.remove('translate-x-0')
    this.panel.classList.add('translate-x-full')
    setTimeout(() => {
      this.container.classList.add('hidden')
    }, 200)
  }
}

Hooks.AmbientAudio = {
  mounted() {
    // Listen for session status changes from LiveView
    this.handleEvent("session_status_changed", ({ status }) => {
      this.handleStatusChange(status)
    })
  },

  handleStatusChange(status) {
    const audio = getGlobalAudio()
    const currentSound = getSavedSound()

    // Only play during :active (work phase), not during :break or :autostart
    if (status === 'active') {
      if (currentSound !== 'none') {
        // Restore volume before playing
        audio.volume = parseInt(getSavedVolume()) / 100

        const soundFile = SOUND_FILES[currentSound]
        if (soundFile) {
          if (audio.src !== window.location.origin + soundFile) {
            audio.src = soundFile
          }
          audio.play().catch(err => console.error('Failed to play ambient audio:', err))
        }
      }
    } else {
      // Fade out during :break and :autostart transitions
      if (!audio.paused) {
        fadeOutAudio(2000) // 2 second fade out
      }
    }
  },

  destroyed() {
    const audio = getGlobalAudio()
    audio.pause()
    audio.currentTime = 0
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

