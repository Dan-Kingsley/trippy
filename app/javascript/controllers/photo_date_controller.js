import { Controller } from "@hotwired/stimulus"

// Reads each photo's EXIF date/time and GPS location directly in the browser
// as soon as they're selected, so the adventurer immediately sees whether
// those will be captured automatically (the authoritative extraction still
// happens server-side, asynchronously, once the photos are actually
// uploaded). If none of the selected photos carry one of those, the matching
// "manually set" toggle is checked for them so they don't have to find it
// themselves - checking is a nudge, never automatic, and never un-checked.
export default class extends Controller {
  static targets = [ "input", "status", "timeCheckbox", "locationCheckbox" ]

  async preview() {
    const files = [ ...this.inputTarget.files ]
    if (files.length === 0) {
      this.statusTarget.classList.add("hidden")
      return
    }

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
