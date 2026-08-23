import { Controller } from "@hotwired/stimulus"

// Wraps a form containing a direct_upload: true file field (trip cover
// photo, profile picture), showing upload progress and keeping the submit
// button disabled until the file has finished uploading straight to
// storage. Direct upload verifies an MD5 checksum server-side before the
// blob is usable, so a connection dropped mid-transfer on patchy internet
// surfaces as a clear error here instead of silently attaching a truncated
// file the way a plain form post would.
export default class extends Controller {
  static targets = [ "progressWrap", "progressBar", "error", "submit" ]

  start() {
    this.submitTarget.disabled = true
    this.errorTarget.classList.add("hidden")
    this.progressWrapTarget.classList.remove("hidden")
    this.progressBarTarget.style.width = "0%"
  }

  progress(event) {
    this.progressBarTarget.style.width = `${Math.round(event.detail.progress)}%`
  }

  error(event) {
    // Rails' own direct-upload JS falls back to window.alert(error) for this
    // event unless it's prevented - we show the message inline instead.
    event.preventDefault()
    this.errorTarget.textContent = event.detail.error
    this.errorTarget.classList.remove("hidden")
    this.progressWrapTarget.classList.add("hidden")
    this.submitTarget.disabled = false
  }

  end() {
    this.submitTarget.disabled = false
  }
}
