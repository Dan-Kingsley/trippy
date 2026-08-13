import { Controller } from "@hotwired/stimulus"

// Horizontal swipeable photo carousel with dot indicators and a fullscreen
// lightbox. Both the inline carousel's prev/next buttons and the lightbox
// loop from the last photo back to the first (and vice versa), and stay in
// sync with each other so closing the lightbox leaves the carousel on the
// same photo. In the lightbox, arrow keys and touch swipes move between
// photos, and tapping/clicking the far left or right 10% of the screen
// steps back/forward - the on-screen arrows there only reveal on hover
// over those edges (see the group-hover classes in the view).
export default class extends Controller {
  static targets = [ "track", "dot", "lightbox", "lightboxImage" ]

  connect() {
    this.index = 0
  }

  get count() {
    return this.trackTarget.children.length
  }

  onScroll = () => {
    const index = Math.round(this.trackTarget.scrollLeft / this.trackTarget.clientWidth)
    this.setIndex(index, { scrollTrack: false })
  }

  goTo(event) {
    this.setIndex(Number(event.currentTarget.dataset.index))
  }

  prev(event) {
    event?.stopPropagation()
    this.step(-1)
  }

  next(event) {
    event?.stopPropagation()
    this.step(1)
  }

  step(direction) {
    const atBoundary = direction < 0 ? this.index <= 0 : this.index >= this.count - 1
    const nextIndex = (this.index + direction + this.count) % this.count
    this.setIndex(nextIndex, { instant: atBoundary })
  }

  setIndex(index, { scrollTrack = true, instant = false } = {}) {
    this.index = ((index % this.count) + this.count) % this.count

    if (scrollTrack) {
      this.trackTarget.scrollTo({ left: this.index * this.trackTarget.clientWidth, behavior: instant ? "auto" : "smooth" })
    }

    this.dotTargets.forEach((dot, i) => {
      dot.classList.toggle("bg-white", i === this.index)
      dot.classList.toggle("bg-white/40", i !== this.index)
    })

    if (!this.lightboxTarget.classList.contains("hidden")) this.updateLightboxImage()
  }

  updateLightboxImage() {
    const image = this.trackTarget.children[this.index]?.querySelector("img")
    if (image) this.lightboxImageTarget.src = image.dataset.fullSrc
  }

  open(event) {
    const index = [ ...this.trackTarget.children ].findIndex((slide) => slide.contains(event.currentTarget))
    if (index !== -1) this.index = index

    this.updateLightboxImage()
    this.lightboxTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.lightboxTarget.classList.add("hidden")
    this.lightboxImageTarget.src = ""
    document.body.classList.remove("overflow-hidden")
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    if (this.lightboxTarget.classList.contains("hidden")) return
    if (event.key === "ArrowLeft") this.step(-1)
    if (event.key === "ArrowRight") this.step(1)
  }

  onTouchStart(event) {
    this.touchStartX = event.touches[0].clientX
  }

  onTouchEnd(event) {
    if (this.touchStartX == null) return

    const dx = event.changedTouches[0].clientX - this.touchStartX
    this.touchStartX = null
    if (Math.abs(dx) < 40) return

    this.step(dx < 0 ? 1 : -1)
  }
}
