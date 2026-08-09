import { Controller } from "@hotwired/stimulus"

// Generic checkbox-driven visibility toggle, e.g. showing manual
// location/time override fields only when their checkbox is checked.
export default class extends Controller {
  static targets = ["revealable"]

  connect() {
    this.sync()
  }

  sync() {
    const show = this.element.querySelector("input[type=checkbox]").checked
    this.revealableTargets.forEach((el) => el.classList.toggle("hidden", !show))
  }
}
