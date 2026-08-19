import { Controller } from "@hotwired/stimulus"

// Generic dropdown menu: a trigger toggles a panel, which closes on an
// outside click or after picking an item (pair the item's action with
// "menu#close", e.g. data-action="modal#open menu#close").
export default class extends Controller {
  static targets = ["panel"]

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
    this.panelTarget.classList.toggle("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }
}
