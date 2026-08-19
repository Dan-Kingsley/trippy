import { Controller } from "@hotwired/stimulus"
import "emoji-picker-element"

// Toggles an <emoji-picker> popover and submits the chosen emoji as a
// reaction, letting people react with any emoji rather than a curated set.
// A custom "Recent" tab (backed by the server-rendered recentPanelTarget)
// sits alongside the library's own "All" picker, since emoji-picker-element
// has no public API for adding a first-class category tab of our own.
export default class extends Controller {
  static targets = ["popover", "picker", "form", "input", "recentTab", "allTab", "recentPanel", "allPanel"]

  connect() {
    this.closeOnOutsideClick = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    document.addEventListener("click", this.closeOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
  }

  toggle(event) {
    event.stopPropagation()
    const opening = this.popoverTarget.classList.contains("hidden")
    if (opening) {
      this.pickerTarget.classList.toggle("dark", document.documentElement.classList.contains("dark"))
    }
    this.popoverTarget.classList.toggle("hidden")
    if (opening) this.reposition()
  }

  // The popover is anchored `left: 0` relative to its trigger by default,
  // which overflows off-screen on narrow/mobile viewports when the trigger
  // sits mid-row. Shift it left/right just enough to stay within the
  // viewport, with a small margin on each side.
  reposition() {
    const popover = this.popoverTarget
    const margin = 8

    popover.style.left = "0px"
    const rect = popover.getBoundingClientRect()

    let shift = 0
    if (rect.right > window.innerWidth - margin) {
      shift = rect.right - (window.innerWidth - margin)
    }
    if (rect.left - shift < margin) {
      shift = rect.left - margin
    }
    popover.style.left = `${-shift}px`
  }

  showRecent() {
    this.recentPanelTarget.classList.remove("hidden")
    this.allPanelTarget.classList.add("hidden")
    this.setActiveTab(this.recentTabTarget, this.allTabTarget)
  }

  showAll() {
    this.allPanelTarget.classList.remove("hidden")
    this.recentPanelTarget.classList.add("hidden")
    this.setActiveTab(this.allTabTarget, this.recentTabTarget)
  }

  setActiveTab(active, inactive) {
    active.classList.add("text-amber-700", "dark:text-amber-400", "border-b-2", "border-amber-600")
    active.classList.remove("text-stone-500", "dark:text-stone-400")
    inactive.classList.remove("text-amber-700", "dark:text-amber-400", "border-b-2", "border-amber-600")
    inactive.classList.add("text-stone-500", "dark:text-stone-400")
  }

  selectRecent(event) {
    this.inputTarget.value = event.currentTarget.dataset.emoji
    this.close()
    this.formTarget.requestSubmit()
  }

  select(event) {
    this.inputTarget.value = event.detail.unicode
    this.close()
    this.formTarget.requestSubmit()
  }

  close() {
    this.popoverTarget.classList.add("hidden")
  }
}
