import { Controller } from "@hotwired/stimulus"

// Fills a datetime-local input with the current local date & time.
export default class extends Controller {
  static targets = [ "input" ]

  set() {
    const d = new Date()
    const pad = (n) => String(n).padStart(2, "0")
    this.inputTarget.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
  }
}
