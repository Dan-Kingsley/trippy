import { Controller } from "@hotwired/stimulus"

// Copies the source target's value/text to the clipboard and briefly
// flashes the button's label to confirm the copy.
export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    const text = this.sourceTarget.value ?? this.sourceTarget.textContent
    navigator.clipboard.writeText(text).then(() => {
      const original = this.buttonTarget.textContent
      this.buttonTarget.textContent = "Copied!"
      setTimeout(() => { this.buttonTarget.textContent = original }, 1500)
    })
  }
}
