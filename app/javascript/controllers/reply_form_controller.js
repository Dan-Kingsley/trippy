import { Controller } from "@hotwired/stimulus"

// Shows/hides a comment's inline reply form when "Reply" is clicked.
export default class extends Controller {
  static targets = [ "form" ]

  toggle() {
    this.formTarget.classList.toggle("hidden")
    if (!this.formTarget.classList.contains("hidden")) {
      this.formTarget.querySelector("textarea")?.focus()
    }
  }
}
