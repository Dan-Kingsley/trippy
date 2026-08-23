import { Controller } from "@hotwired/stimulus"

// Splits a single datetime value across two native inputs - <input
// type="date"> and <input type="time"> - instead of a single
// <input type="datetime-local">. Both those types have far more consistent
// native picker support and a spec-guaranteed value format (YYYY-MM-DD and
// HH:MM respectively) across browsers/OSes than datetime-local, whose picker
// UI and typed-text format vary enough across platforms to produce a value
// the backend can't parse. The two visible inputs stay combined into a
// single hidden field in that same "YYYY-MM-DDTHH:MM" format, so the actual
// submitted param and its parsing on the backend are unchanged.
export default class extends Controller {
  static targets = [ "date", "time", "hidden" ]

  connect() {
    const [ date, time ] = this.hiddenTarget.value.split("T")
    if (date) this.dateTarget.value = date
    if (time) this.timeTarget.value = time.slice(0, 5)
  }

  combine() {
    this.hiddenTarget.value = this.dateTarget.value && this.timeTarget.value
      ? `${this.dateTarget.value}T${this.timeTarget.value}`
      : ""
  }

  setNow() {
    const d = new Date()
    const pad = (n) => String(n).padStart(2, "0")
    this.dateTarget.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    this.timeTarget.value = `${pad(d.getHours())}:${pad(d.getMinutes())}`
    this.combine()
  }
}
