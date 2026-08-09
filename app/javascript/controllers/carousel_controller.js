import { Controller } from "@hotwired/stimulus"

// Horizontal swipeable photo carousel with dot indicators and a fullscreen lightbox.
export default class extends Controller {
  static targets = ["track", "dot", "lightbox", "lightboxImage"]

  connect() {
    this.trackTarget.addEventListener("scroll", this.onScroll)
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this.onScroll)
  }

  onScroll = () => {
    const index = Math.round(this.trackTarget.scrollLeft / this.trackTarget.clientWidth)
    this.dotTargets.forEach((dot, i) => dot.classList.toggle("bg-white", i === index) || dot.classList.toggle("bg-white/40", i !== index))
  }

  goTo(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.trackTarget.scrollTo({ left: index * this.trackTarget.clientWidth, behavior: "smooth" })
  }

  prev() {
    this.trackTarget.scrollBy({ left: -this.trackTarget.clientWidth, behavior: "smooth" })
  }

  next() {
    this.trackTarget.scrollBy({ left: this.trackTarget.clientWidth, behavior: "smooth" })
  }

  open(event) {
    this.lightboxImageTarget.src = event.currentTarget.dataset.fullSrc
    this.lightboxTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.lightboxTarget.classList.add("hidden")
    this.lightboxImageTarget.src = ""
    document.body.classList.remove("overflow-hidden")
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
