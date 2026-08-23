import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

// Reads each photo's EXIF date/time and GPS location directly in the browser
// as soon as they're selected, so the adventurer immediately sees whether
// those will be captured automatically (the authoritative extraction still
// happens server-side, asynchronously, once the photos are actually
// uploaded). If none of the selected photos carry one of those, the matching
// "manually set" toggle is checked for them so they don't have to find it
// themselves - checking is a nudge, never automatic, and never un-checked.
//
// Selected files also upload straight to storage here (one DirectUpload per
// file, each with its own progress bar), rather than waiting to be posted as
// part of the surrounding form - a checksum is verified server-side before
// each blob is usable, so a connection dropped partway through on patchy
// internet fails that file with a clear error instead of silently attaching
// a truncated one. Successful uploads are referenced from the form via a
// hidden photo_signed_ids[] field per file, and the original file input is
// cleared so its (now-redundant) raw bytes aren't also posted - if this
// script never runs at all, that input is untouched and the plain multipart
// upload it was always capable of still works as a fallback.
export default class extends Controller {
  static targets = [ "input", "status", "timeCheckbox", "locationCheckbox", "fileCount", "uploadList", "submit" ]
  static values = { directUploadUrl: String }

  connect() {
    this.onPaste = this.onPaste.bind(this)
    this.element.addEventListener("paste", this.onPaste)
    this.defaultFileCountText = this.hasFileCountTarget ? this.fileCountTarget.textContent : null
    this.pendingUploads = 0
  }

  disconnect() {
    this.element.removeEventListener("paste", this.onPaste)
  }

  // Lets adventurers paste a screenshot or copied image straight into the
  // form instead of having to save it and re-select it as a file - merges
  // pasted images in with whatever's already selected, then feeds the same
  // file input through the normal change->preview pipeline.
  onPaste(event) {
    const images = [ ...event.clipboardData?.items || [] ]
      .filter((item) => item.type.startsWith("image/"))
      .map((item) => item.getAsFile())
      .filter(Boolean)

    if (images.length === 0) return
    event.preventDefault()

    const combined = new DataTransfer()
    for (const file of this.inputTarget.files) combined.items.add(file)
    images.forEach((file, i) => combined.items.add(new File([ file ], file.name || `pasted-image-${Date.now()}-${i}.png`, { type: file.type })))

    this.inputTarget.files = combined.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  async preview() {
    const files = [ ...this.inputTarget.files ]

    if (this.hasFileCountTarget) {
      this.fileCountTarget.textContent = files.length === 0
        ? this.defaultFileCountText
        : `${files.length} file${files.length === 1 ? "" : "s"} selected`
    }

    if (files.length === 0) {
      this.statusTarget.classList.add("hidden")
      return
    }

    this.uploadFiles(files)

    this.statusTarget.textContent = "Reading photo date & location…"
    this.statusTarget.classList.remove("hidden")

    let takenAt = null
    let location = null
    for (const file of files) {
      const exif = await this.readExif(file).catch(() => ({ takenAt: null, location: null }))
      takenAt ||= exif.takenAt
      location ||= exif.location
      if (takenAt && location) break
    }

    const found = []
    const missing = []
    if (takenAt) {
      found.push(`📅 ${takenAt.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })}`)
    } else {
      missing.push("date")
    }
    if (location) {
      found.push("📍 location")
    } else {
      missing.push("location")
    }

    let message = found.length ? `${found.join(" and ")} — read from your photos.` : ""
    if (missing.length) {
      message += `${message ? " No" : "No"} ${missing.join(" or ")} found in your photos — you can set ${missing.length > 1 ? "them" : "it"} manually below.`
    }
    this.statusTarget.textContent = message

    if (!takenAt && this.hasTimeCheckboxTarget && !this.timeCheckboxTarget.checked) {
      this.check(this.timeCheckboxTarget)
    }
    if (!location && this.hasLocationCheckboxTarget && !this.locationCheckboxTarget.checked) {
      this.check(this.locationCheckboxTarget)
    }
  }

  uploadFiles(files) {
    if (!this.hasDirectUploadUrlValue || !this.hasUploadListTarget) return

    this.uploadListTarget.innerHTML = ""
    this.uploadListTarget.classList.remove("hidden")
    this.pendingUploads += files.length
    this.setSubmitDisabled(true)

    files.forEach((file) => this.uploadFile(file))

    // The DirectUpload calls above already have their own reference to each
    // File object, so it's safe to clear the input now rather than waiting
    // for them to finish - this is what keeps these files from also being
    // posted as raw multipart bytes once their signed IDs are in the form.
    this.inputTarget.value = ""
  }

  uploadFile(file) {
    const row = this.buildProgressRow(file.name)
    this.uploadListTarget.appendChild(row.element)

    const upload = new DirectUpload(file, this.directUploadUrlValue, {
      directUploadWillStoreFileWithXHR: (xhr) => {
        xhr.upload.addEventListener("progress", (event) => {
          if (!event.lengthComputable) return
          row.bar.style.width = `${Math.round((event.loaded / event.total) * 100)}%`
        })
      }
    })

    upload.create((error, blob) => {
      if (error) {
        row.bar.classList.replace("bg-amber-600", "bg-red-600")
        row.label.textContent = `${file.name} — upload failed (${error})`
      } else {
        row.bar.style.width = "100%"
        const hidden = document.createElement("input")
        hidden.type = "hidden"
        hidden.name = "photo_signed_ids[]"
        hidden.value = blob.signed_id
        this.element.appendChild(hidden)
      }

      this.pendingUploads = Math.max(0, this.pendingUploads - 1)
      if (this.pendingUploads === 0) this.setSubmitDisabled(false)
    })
  }

  buildProgressRow(name) {
    const element = document.createElement("div")
    element.className = "flex items-center gap-2 text-xs text-stone-500 dark:text-stone-400"

    const label = document.createElement("span")
    label.className = "truncate flex-1"
    label.textContent = name
    element.appendChild(label)

    const track = document.createElement("div")
    track.className = "w-24 h-1.5 rounded-full bg-stone-200 dark:bg-stone-800 overflow-hidden shrink-0"
    const bar = document.createElement("div")
    bar.className = "h-full bg-amber-600 transition-all"
    bar.style.width = "0%"
    track.appendChild(bar)
    element.appendChild(track)

    return { element, label, bar }
  }

  setSubmitDisabled(disabled) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = disabled
  }

  // Ticks a checkbox programmatically and fires the events a real click
  // would - Stimulus's default action for a bare <input> is "input", not
  // "change", so both are dispatched to match native checkbox behaviour.
  check(checkbox) {
    checkbox.checked = true
    checkbox.dispatchEvent(new Event("input", { bubbles: true }))
    checkbox.dispatchEvent(new Event("change", { bubbles: true }))
  }

  async readExif(file) {
    const buffer = await file.slice(0, 262144).arrayBuffer()
    const view = new DataView(buffer)
    if (view.getUint16(0) !== 0xffd8) return { takenAt: null, location: null } // not a JPEG

    let offset = 2
    while (offset + 4 <= view.byteLength) {
      const marker = view.getUint16(offset)
      if (marker === 0xffda) break // start of scan - no more metadata ahead

      const length = view.getUint16(offset + 2)
      if (marker === 0xffe1 && this.asciiAt(view, offset + 4, 4) === "Exif") {
        return this.parseTiff(view, offset + 4 + 6)
      }
      offset += 2 + length
    }
    return { takenAt: null, location: null }
  }

  parseTiff(view, tiffStart) {
    const little = this.asciiAt(view, tiffStart, 2) === "II"
    const ifd0Offset = view.getUint32(tiffStart + 4, little)
    const ifd0 = this.readIfd(view, tiffStart, tiffStart + ifd0Offset, little)

    let takenAt = null
    const exifIfdPointer = ifd0.get(0x8769)
    if (exifIfdPointer != null) {
      const exifIfd = this.readIfd(view, tiffStart, tiffStart + exifIfdPointer, little)
      const raw = exifIfd.get(0x9003) || exifIfd.get(0x9004)
      if (raw) takenAt = this.parseExifDate(raw)
    }
    if (!takenAt) {
      const plain = ifd0.get(0x0132)
      if (plain) takenAt = this.parseExifDate(plain)
    }

    const location = this.parseGps(view, tiffStart, ifd0, little)

    return { takenAt, location }
  }

  parseGps(view, tiffStart, ifd0, little) {
    const gpsIfdPointer = ifd0.get(0x8825)
    if (gpsIfdPointer == null) return null

    const gpsIfd = this.readIfd(view, tiffStart, tiffStart + gpsIfdPointer, little)
    const lat = gpsIfd.get(0x0002)
    const latRef = gpsIfd.get(0x0001)
    const lng = gpsIfd.get(0x0004)
    const lngRef = gpsIfd.get(0x0003)
    if (!lat || !lng) return null

    const toDecimal = ([ deg, min, sec ], ref) => {
      const value = deg + min / 60 + sec / 3600
      return ref === "S" || ref === "W" ? -value : value
    }
    return { lat: toDecimal(lat, latRef), lng: toDecimal(lng, lngRef) }
  }

  readIfd(view, tiffStart, ifdOffset, little) {
    const entries = new Map()
    if (ifdOffset + 2 > view.byteLength) return entries
    const count = view.getUint16(ifdOffset, little)

    for (let i = 0; i < count; i++) {
      const entryOffset = ifdOffset + 2 + i * 12
      if (entryOffset + 12 > view.byteLength) break

      const tag = view.getUint16(entryOffset, little)
      const type = view.getUint16(entryOffset + 2, little)
      const numValues = view.getUint32(entryOffset + 4, little)
      const valueOffset = entryOffset + 8

      if (type === 2) { // ASCII
        const dataOffset = numValues > 4 ? tiffStart + view.getUint32(valueOffset, little) : valueOffset
        if (dataOffset + numValues <= view.byteLength) {
          entries.set(tag, this.asciiAt(view, dataOffset, numValues).replace(/\0+$/, ""))
        }
      } else if (type === 4 && numValues === 1) { // LONG
        entries.set(tag, view.getUint32(valueOffset, little))
      } else if (type === 3 && numValues === 1) { // SHORT
        entries.set(tag, view.getUint16(valueOffset, little))
      } else if (type === 5 && numValues === 3) { // RATIONAL[3] - GPS degrees/minutes/seconds
        const dataOffset = tiffStart + view.getUint32(valueOffset, little)
        if (dataOffset + 24 <= view.byteLength) {
          const parts = [ 0, 1, 2 ].map((v) => {
            const num = view.getUint32(dataOffset + v * 8, little)
            const den = view.getUint32(dataOffset + v * 8 + 4, little)
            return den === 0 ? 0 : num / den
          })
          entries.set(tag, parts)
        }
      }
    }

    return entries
  }

  asciiAt(view, offset, length) {
    let s = ""
    for (let i = 0; i < length; i++) s += String.fromCharCode(view.getUint8(offset + i))
    return s
  }

  parseExifDate(raw) {
    const match = raw.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/)
    if (!match) return null
    const [ y, mo, d, h, mi, s ] = match.slice(1).map(Number)
    return new Date(y, mo - 1, d, h, mi, s)
  }
}
