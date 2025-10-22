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
    this.updateTimer()
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
    this.storageKey = `participant-card-collapsed-${this.el.dataset.participantId}`

    // Load saved state from sessionStorage (auto-clears when tab closes)
    const isCollapsed = sessionStorage.getItem(this.storageKey) === 'true'
    if (isCollapsed) {
      this.el.dataset.collapsed = 'true'
    }

    // Add click handler for collapse button
    this.el.querySelector('.collapse-toggle').addEventListener('click', (e) => {
      e.preventDefault()
      const currentlyCollapsed = this.el.dataset.collapsed === 'true'
      this.el.dataset.collapsed = !currentlyCollapsed
      sessionStorage.setItem(this.storageKey, !currentlyCollapsed)
    })
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

