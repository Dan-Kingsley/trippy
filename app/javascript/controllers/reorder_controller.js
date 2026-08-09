import { Controller } from "@hotwired/stimulus"

// Drag-and-drop reordering of an entry's photos. On drop, persists the new
// position of every item (first photo in order becomes the trip's thumbnail
// candidate when no explicit cover photo is set).
export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.itemTargets.forEach((item) => {
      item.setAttribute("draggable", "true")
      item.addEventListener("dragstart", this.onDragStart)
      item.addEventListener("dragover", this.onDragOver)
      item.addEventListener("drop", this.onDrop)
      item.addEventListener("dragend", this.onDragEnd)
    })
  }

  onDragStart = (event) => {
    this.dragged = event.currentTarget
    event.currentTarget.classList.add("opacity-40")
  }

  onDragOver = (event) => {
    event.preventDefault()
    const target = event.currentTarget
    if (target === this.dragged) return
    const rect = target.getBoundingClientRect()
    const before = (event.clientX - rect.left) < rect.width / 2
    target.parentNode.insertBefore(this.dragged, before ? target : target.nextSibling)
  }

  onDrop = (event) => {
    event.preventDefault()
  }

  onDragEnd = (event) => {
    event.currentTarget.classList.remove("opacity-40")
    this.persistPositions()
  }

  persistPositions() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    this.itemTargets.forEach((item, index) => {
      fetch(item.dataset.url, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ position: index })
      })
    })
  }
}
