import { Controller } from "@hotwired/stimulus"

// Wraps a native <dialog> so a trigger button elsewhere in the same
// controller scope can open/close it, including on backdrop click.
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.dialogTarget.addEventListener("click", this.closeOnBackdrop)
  }

  disconnect() {
    this.dialogTarget.removeEventListener("click", this.closeOnBackdrop)
  }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop = (event) => {
    if (event.target === this.dialogTarget) this.close()
  }
}
