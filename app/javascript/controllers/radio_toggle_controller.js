import { Controller } from "@hotwired/stimulus"

// Generic radio-driven visibility toggle: each panel target only shows when
// the checked radio's value matches its data-radio-toggle-value attribute.
// Used for mutually-exclusive option groups (e.g. a trip's cover image
// source) where more than two choices are possible, unlike the
// checkbox-driven "toggle" controller.
export default class extends Controller {
  static targets = [ "panel" ]

  connect() {
    this.sync()
  }

  sync() {
    const checked = this.element.querySelector("input[type=radio]:checked")
    const value = checked?.value

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.radioToggleValue !== value)
    })
  }
}
