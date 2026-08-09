import { Controller } from "@hotwired/stimulus"

// Reads each photo's EXIF date/time directly in the browser as soon as it's
// selected, so the adventurer immediately sees that the date & time will be
// captured automatically (the authoritative extraction still happens
// server-side, asynchronously, once the photo is actually uploaded).
export default class extends Controller {
  static targets = [ "input", "status" ]

  async preview() {
    const file = this.inputTarget.files[0]
    if (!file) {
      this.statusTarget.classList.add("hidden")
      return
    }

    this.statusTarget.textContent = "Reading photo date & time…"
    this.statusTarget.classList.remove("hidden")

    const takenAt = await this.readDateTime(file).catch(() => null)

    if (takenAt) {
      const formatted = takenAt.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })
      this.statusTarget.textContent = `📅 ${formatted} — read from this photo's metadata.`
    } else {
      this.statusTarget.textContent = "No date found in this photo — you can set it manually below."
    }
  }

  async readDateTime(file) {
    const buffer = await file.slice(0, 262144).arrayBuffer()
    const view = new DataView(buffer)
    if (view.getUint16(0) !== 0xffd8) return null // not a JPEG

    let offset = 2
    while (offset + 4 <= view.byteLength) {
      const marker = view.getUint16(offset)
      if (marker === 0xffda) break // start of scan - no more metadata ahead

      const length = view.getUint16(offset + 2)
      if (marker === 0xffe1 && this.asciiAt(view, offset + 4, 4) === "Exif") {
        const date = this.parseTiff(view, offset + 4 + 6)
        if (date) return date
      }
      offset += 2 + length
    }
    return null
  }

  parseTiff(view, tiffStart) {
    const little = this.asciiAt(view, tiffStart, 2) === "II"
    const ifd0Offset = view.getUint32(tiffStart + 4, little)
    const ifd0 = this.readIfd(view, tiffStart, tiffStart + ifd0Offset, little)

    const exifIfdPointer = ifd0.get(0x8769)
    if (exifIfdPointer != null) {
      const exifIfd = this.readIfd(view, tiffStart, tiffStart + exifIfdPointer, little)
      const raw = exifIfd.get(0x9003) || exifIfd.get(0x9004)
      if (raw) return this.parseExifDate(raw)
    }

    const plain = ifd0.get(0x0132)
    return plain ? this.parseExifDate(plain) : null
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
