import { Controller } from "@hotwired/stimulus"
import "emoji-picker-element"

// Toggles an <emoji-picker> popover and submits the chosen emoji as a
// reaction, letting people react with any emoji rather than a curated set.
export default class extends Controller {
  static targets = ["popover", "picker", "form", "input"]

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
    if (this.popoverTarget.classList.contains("hidden")) {
      this.pickerTarget.classList.toggle("dark", document.documentElement.classList.contains("dark"))
    }
    this.popoverTarget.classList.toggle("hidden")
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
