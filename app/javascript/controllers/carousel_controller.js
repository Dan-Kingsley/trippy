import { Controller } from "@hotwired/stimulus"

const MIN_SCALE = 1
const MAX_SCALE = 4
const KEYBOARD_ZOOM_STEP = 0.75
const WHEEL_ZOOM_SPEED = 0.0025

// Horizontal swipeable photo/video carousel with dot indicators and a
// fullscreen lightbox. The inline carousel's prev/next buttons, dots, swipe,
// and ArrowLeft/ArrowRight (while it has keyboard focus) move between
// slides - but once the lightbox is open, the user is "clicked in" to that
// one photo/video and none of that navigation is available; the only way to
// see another one is to close the lightbox and click into it from the
// inline carousel.
//
// Photos: pinch (or ArrowUp/ArrowDown) zooms into the lightbox photo,
// anchored to the pinch midpoint so it zooms into wherever the fingers are
// rather than always the image center, and dragging with one finger pans
// around while zoomed in; lifting one finger mid-pinch hands off to a
// single-finger pan using the remaining finger rather than requiring a
// fresh touch. The mouse wheel zooms in/out centered on the cursor
// position, and once zoomed in, click-and-drag pans the image; a drag is
// not treated as a click so it doesn't also close the lightbox. Zoom always
// resets when the lightbox closes.
//
// Videos: shown inline as a poster frame with a play icon overlay and never
// autoplay there. Opening one into the lightbox loads it and plays it
// automatically once ready (this is not "inline autoplay" - it's the direct
// result of the click that opened it) with a bottom scrubber to seek; it
// doesn't autoplay again if reopened, and ending playback swaps the icon to
// a restart button. Clicking the video itself (anywhere but that icon or
// the scrubber) closes the lightbox exactly like clicking a photo does.
export default class extends Controller {
  static targets = [
    "track", "dot", "lightbox", "lightboxImage",
    "lightboxVideoWrap", "lightboxVideo", "videoIcon", "scrubberWrap", "scrubber", "currentTime", "duration"
  ]

  connect() {
    this.index = 0
    this.scale = MIN_SCALE
    this.translateX = 0
    this.translateY = 0
    this.kind = "image"
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
  }

  open(event) {
    const slide = this.trackTarget.children[
      [ ...this.trackTarget.children ].findIndex((s) => s.contains(event.currentTarget))
    ]
    const index = [ ...this.trackTarget.children ].indexOf(slide)
    if (index !== -1) this.index = index

    this.kind = slide?.dataset.kind || "image"
    this.resetZoom()

    if (this.kind === "video") {
      this.lightboxImageTarget.classList.add("hidden")
      this.lightboxVideoWrapTarget.classList.remove("hidden")
      this.openVideo(slide.dataset.videoSrc)
    } else {
      this.lightboxVideoWrapTarget.classList.add("hidden")
      this.lightboxImageTarget.classList.remove("hidden")
      this.lightboxImageTarget.src = slide.dataset.fullSrc
    }

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
    if (this.kind === "video") this.closeVideo()
    document.body.classList.remove("overflow-hidden")
  }

  // --- Video -----------------------------------------------------------

  openVideo(src) {
    this.autoplayedThisOpen = false
    this.videoIconTarget.classList.add("hidden")
    this.scrubberWrapTarget.classList.add("hidden")
    this.scrubberTarget.value = 0
    this.currentTimeTarget.textContent = "0:00"
    this.durationTarget.textContent = "0:00"

    this.lightboxVideoTarget.src = src
    this.lightboxVideoTarget.load()
  }

  closeVideo() {
    this.lightboxVideoTarget.pause()
    this.lightboxVideoTarget.removeAttribute("src")
    this.lightboxVideoTarget.load()
  }

  // Plays automatically the first time this open()'s video is ready -
  // triggered by the click that opened the lightbox, not inline autoplay.
  onVideoCanPlay() {
    if (this.autoplayedThisOpen) return
    this.autoplayedThisOpen = true
    this.lightboxVideoTarget.play()
  }

  onVideoLoadedMetadata() {
    this.scrubberTarget.max = this.lightboxVideoTarget.duration || 0
    this.durationTarget.textContent = this.formatTime(this.lightboxVideoTarget.duration)
    this.scrubberWrapTarget.classList.remove("hidden")
  }

  onVideoPlay() {
    this.videoIconTarget.classList.add("hidden")
  }

  onVideoEnded() {
    this.videoIconTarget.classList.remove("hidden")
  }

  onVideoTimeUpdate() {
    if (this.scrubbing) return
    this.scrubberTarget.value = this.lightboxVideoTarget.currentTime
    this.currentTimeTarget.textContent = this.formatTime(this.lightboxVideoTarget.currentTime)
  }

  // The restart button shown once a video ends - visually the same play
  // icon, but here it always means "start over" since it only appears then.
  restartVideo(event) {
    event.stopPropagation()
    this.lightboxVideoTarget.currentTime = 0
    this.lightboxVideoTarget.play()
  }

  seek(event) {
    event.stopPropagation()
    this.lightboxVideoTarget.currentTime = Number(event.target.value)
    this.currentTimeTarget.textContent = this.formatTime(this.lightboxVideoTarget.currentTime)
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  formatTime(seconds) {
    if (!Number.isFinite(seconds)) return "0:00"
    const total = Math.max(0, Math.round(seconds))
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`
  }

  // --- Photo zoom/pan (images only) -------------------------------------

  onKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    const lightboxOpen = !this.lightboxTarget.classList.contains("hidden")

    if (lightboxOpen) {
      // No prev/next while clicked in - only zoom (photos) and Escape apply.
      if (this.kind !== "image") return
      if (event.key === "ArrowUp") { event.preventDefault(); this.applyZoom(this.scale + KEYBOARD_ZOOM_STEP) }
      if (event.key === "ArrowDown") { event.preventDefault(); this.applyZoom(this.scale - KEYBOARD_ZOOM_STEP) }
      return
    }

    if (!this.element.contains(document.activeElement)) return
    if (event.key === "ArrowLeft") { event.preventDefault(); this.step(-1) }
    if (event.key === "ArrowRight") { event.preventDefault(); this.step(1) }
  }

  // A single finger pans (when zoomed in) - no swipe-to-navigate here, since
  // the lightbox these touch handlers belong to disables navigation while
  // open. A second finger arriving mid-touch fires its own touchstart with
  // both touches present, which is how we detect the start of a pinch.
  onTouchStart(event) {
    if (this.kind !== "image") return

    if (event.touches.length === 2) {
      this.pinching = true
      this.pinchStartDistance = this.touchDistance(event.touches)
      this.pinchStartScale = this.scale
      this.pinchStartTranslateX = this.translateX
      this.pinchStartTranslateY = this.translateY

      const mid = this.touchMidpoint(event.touches)
      this.pinchStartMidX = mid.x
      this.pinchStartMidY = mid.y

      const rect = this.lightboxImageTarget.getBoundingClientRect()
      this.pinchStartCenterX = rect.left + rect.width / 2
      this.pinchStartCenterY = rect.top + rect.height / 2
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
    }
  }

  onTouchMove(event) {
    if (this.kind !== "image") return

    if (this.pinching && event.touches.length === 2) {
      event.preventDefault()

      const distance = this.touchDistance(event.touches)
      const newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.pinchStartScale * (distance / this.pinchStartDistance)))
      const ratio = newScale / this.pinchStartScale

      // Keep the point under the fingers fixed on screen as the scale
      // changes, and follow the pinch midpoint as it moves, so pinching
      // zooms into (and pans with) where the fingers actually are rather
      // than always zooming straight into the image center.
      const mid = this.touchMidpoint(event.touches)
      this.translateX = this.pinchStartTranslateX + (mid.x - this.pinchStartMidX) +
        (this.pinchStartMidX - this.pinchStartCenterX) * (1 - ratio)
      this.translateY = this.pinchStartTranslateY + (mid.y - this.pinchStartMidY) +
        (this.pinchStartMidY - this.pinchStartCenterY) * (1 - ratio)

      this.applyZoom(newScale)
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
    if (this.kind !== "image") return

    if (this.pinching) {
      // A second finger lifting off a pinch fires its own touchend while one
      // finger remains down - hand off to a single-finger pan from here
      // instead of waiting for a fresh touchstart, so zoom and pan feel like
      // one continuous gesture.
      if (event.touches.length === 1) {
        this.pinching = false
        this.panStart = {
          x: event.touches[0].clientX,
          y: event.touches[0].clientY,
          translateX: this.translateX,
          translateY: this.translateY
        }
        return
      }

      this.pinching = false
      this.pinchStartDistance = null
      if (this.scale <= MIN_SCALE) this.resetZoom()
      return
    }

    if (this.panStart) {
      this.panStart = null
    }
  }

  touchDistance(touches) {
    return Math.hypot(touches[0].clientX - touches[1].clientX, touches[0].clientY - touches[1].clientY)
  }

  touchMidpoint(touches) {
    return {
      x: (touches[0].clientX + touches[1].clientX) / 2,
      y: (touches[0].clientY + touches[1].clientY) / 2
    }
  }

  onWheel(event) {
    if (this.kind !== "image") return
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
    if (this.kind !== "image" || this.scale <= MIN_SCALE) return

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
