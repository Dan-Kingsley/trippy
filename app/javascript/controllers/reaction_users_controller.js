import { Controller } from "@hotwired/stimulus"

const LONG_PRESS_MS = 500
const MOVE_THRESHOLD = 10

// Lets trip admins/owners/collaborators right-click (desktop) or long-press
// (touch) an emoji reaction to see who reacted with it, in a shared dialog.
// Only rendered for users who can edit the trip - see trip_entries/show.
export default class extends Controller {
  static targets = ["dialog", "content"]
  static values = { usersUrl: String, translations: Object }

  show(event) {
    event.preventDefault()
    this.load(event.currentTarget.dataset.emoji)
  }

  load(emoji) {
    this.contentTarget.textContent = this.translationsValue.loading
    this.dialogTarget.showModal()

    fetch(`${this.usersUrlValue}?emoji=${encodeURIComponent(emoji)}`, { headers: { Accept: "text/html" } })
      .then((response) => {
        if (!response.ok) throw new Error(`Request failed: ${response.status}`)
        return response.text()
      })
      .then((html) => { this.contentTarget.innerHTML = html })
      .catch(() => { this.contentTarget.textContent = this.translationsValue.load_failed })
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  onTouchStart(event) {
    this.touchStart = { x: event.touches[0].clientX, y: event.touches[0].clientY }
    this.pressEmoji = event.currentTarget.dataset.emoji
    this.longPressFired = false
    this.longPressTimer = setTimeout(() => {
      this.longPressFired = true
      this.load(this.pressEmoji)
    }, LONG_PRESS_MS)
  }

  onTouchMove(event) {
    if (!this.touchStart) return
    const dx = event.touches[0].clientX - this.touchStart.x
    const dy = event.touches[0].clientY - this.touchStart.y
    if (Math.hypot(dx, dy) > MOVE_THRESHOLD) this.cancelLongPress()
  }

  onTouchEnd() {
    this.cancelLongPress()
  }

  onClick(event) {
    if (this.longPressFired) {
      event.preventDefault()
      event.stopPropagation()
      this.longPressFired = false
    }
  }

  cancelLongPress() {
    clearTimeout(this.longPressTimer)
    this.touchStart = null
  }
}
