import { Controller } from "@hotwired/stimulus"

const MIN_SCALE = 1
const MAX_SCALE = 4
const KEYBOARD_ZOOM_STEP = 0.75
const WHEEL_ZOOM_SPEED = 0.0025
const SWIPE_THRESHOLD = 40

// Horizontal swipeable photo carousel with dot indicators and a fullscreen
// lightbox. Both the inline carousel's prev/next buttons and the lightbox
// loop from the last photo back to the first (and vice versa), and stay in
// sync with each other so closing the lightbox leaves the carousel on the
// same photo. In the lightbox, arrow keys and touch swipes move between
// photos, and tapping/clicking the far left or right 10% of the screen
// steps back/forward - the on-screen arrows there only reveal on hover
// over those edges (see the group-hover classes in the view). Pinch (or
// ArrowUp/ArrowDown) zooms into the current lightbox photo, and dragging
// with one finger pans around while zoomed in; zoom always resets when the
// photo changes or the lightbox closes. The inline carousel (lightbox
// closed) also responds to ArrowLeft/ArrowRight while it has keyboard focus.
// The mouse wheel zooms in/out centered on the cursor position, and once
// zoomed in, click-and-drag pans the image; a drag is not treated as a
// click so it doesn't also close the lightbox.
export default class extends Controller {
  static targets = [ "track", "dot", "lightbox", "lightboxImage" ]

  connect() {
    this.index = 0
    this.scale = MIN_SCALE
    this.translateX = 0
    this.translateY = 0
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
    this.resetZoom()

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

    this.resetZoom()
    this.updateLightboxImage()
    this.lightboxTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    if (this.suppressClick) {
      this.suppressClick = false
      return
    }

    this.lightboxTarget.classList.add("hidden")
    this.lightboxImageTarget.src = ""
    this.resetZoom()
    document.body.classList.remove("overflow-hidden")
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    const lightboxOpen = !this.lightboxTarget.classList.contains("hidden")

    if (lightboxOpen) {
      if (event.key === "ArrowLeft") { event.preventDefault(); this.step(-1) }
      if (event.key === "ArrowRight") { event.preventDefault(); this.step(1) }
      if (event.key === "ArrowUp") { event.preventDefault(); this.applyZoom(this.scale + KEYBOARD_ZOOM_STEP) }
      if (event.key === "ArrowDown") { event.preventDefault(); this.applyZoom(this.scale - KEYBOARD_ZOOM_STEP) }
      return
    }

    if (!this.element.contains(document.activeElement)) return
    if (event.key === "ArrowLeft") { event.preventDefault(); this.step(-1) }
    if (event.key === "ArrowRight") { event.preventDefault(); this.step(1) }
  }

  // A single finger starts either a swipe (not zoomed) or a pan (zoomed in).
  // A second finger arriving mid-touch fires its own touchstart with both
  // touches present, which is how we detect the start of a pinch.
  onTouchStart(event) {
    if (event.touches.length === 2) {
      this.pinching = true
      this.touchStartX = null
      this.pinchStartDistance = this.touchDistance(event.touches)
      this.pinchStartScale = this.scale
      return
    }

    this.pinching = false
    if (this.scale > MIN_SCALE) {
      this.panStart = {
        x: event.touches[0].clientX,
        y: event.touches[0].clientY,
        translateX: this.translateX,
        translateY: this.translateY
      }
    } else {
      this.touchStartX = event.touches[0].clientX
    }
  }

  onTouchMove(event) {
    if (this.pinching && event.touches.length === 2) {
      event.preventDefault()
      const distance = this.touchDistance(event.touches)
      this.applyZoom(this.pinchStartScale * (distance / this.pinchStartDistance))
      return
    }

    if (this.panStart && event.touches.length === 1) {
      event.preventDefault()
      this.translateX = this.panStart.translateX + (event.touches[0].clientX - this.panStart.x)
      this.translateY = this.panStart.translateY + (event.touches[0].clientY - this.panStart.y)
      this.applyTransform()
    }
  }

  onTouchEnd(event) {
    if (this.pinching) {
      this.pinching = false
      this.pinchStartDistance = null
      if (this.scale <= MIN_SCALE) this.resetZoom()
      return
    }

    if (this.panStart) {
      this.panStart = null
      return
    }

    if (this.touchStartX == null) return

    const dx = event.changedTouches[0].clientX - this.touchStartX
    this.touchStartX = null
    if (Math.abs(dx) < SWIPE_THRESHOLD) return

    this.step(dx < 0 ? 1 : -1)
  }

  touchDistance(touches) {
    return Math.hypot(touches[0].clientX - touches[1].clientX, touches[0].clientY - touches[1].clientY)
  }

  onWheel(event) {
    event.preventDefault()

    const oldScale = this.scale
    const newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, oldScale - event.deltaY * WHEEL_ZOOM_SPEED))
    if (newScale === oldScale) return

    // Keep the point under the cursor fixed on screen as the scale changes,
    // so zooming feels anchored to the mouse rather than the image center.
    const rect = this.lightboxImageTarget.getBoundingClientRect()
    const centerX = rect.left + rect.width / 2
    const centerY = rect.top + rect.height / 2
    const ratio = newScale / oldScale
    this.translateX += (event.clientX - centerX) * (1 - ratio)
    this.translateY += (event.clientY - centerY) * (1 - ratio)

    this.applyZoom(newScale)
  }

  onMouseDown(event) {
    if (this.scale <= MIN_SCALE) return

    event.preventDefault()
    this.dragging = true
    this.dragMoved = false
    this.panStart = {
      x: event.clientX,
      y: event.clientY,
      translateX: this.translateX,
      translateY: this.translateY
    }
  }

  onMouseMove(event) {
    if (!this.dragging) return

    event.preventDefault()
    this.dragMoved = true
    this.translateX = this.panStart.translateX + (event.clientX - this.panStart.x)
    this.translateY = this.panStart.translateY + (event.clientY - this.panStart.y)
    this.applyTransform()
  }

  onMouseUp() {
    if (!this.dragging) return

    this.dragging = false
    this.panStart = null
    // A click fires right after this mouseup; suppress the one that would
    // otherwise close the lightbox when the mouseup ends a drag.
    if (this.dragMoved) this.suppressClick = true
  }

  applyZoom(scale) {
    this.scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale))
    if (this.scale === MIN_SCALE) {
      this.translateX = 0
      this.translateY = 0
    }
    this.lightboxImageTarget.classList.toggle("cursor-grab", this.scale > MIN_SCALE)
    this.applyTransform()
  }

  applyTransform() {
    this.lightboxImageTarget.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
  }

  resetZoom() {
    this.scale = MIN_SCALE
    this.translateX = 0
    this.translateY = 0
    this.lightboxImageTarget.classList.remove("cursor-grab")
    this.lightboxImageTarget.style.transform = ""
  }
}
