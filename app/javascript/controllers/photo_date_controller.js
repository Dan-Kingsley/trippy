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
  static targets = [ "input", "status", "timeCheckbox", "locationManualRadio", "fileCount", "uploadList", "submit" ]
  // autoSubmit: when true, the surrounding form submits itself as soon as
  // every selected file finishes uploading, with no manual "Upload" click
  // needed - only set on forms whose sole purpose is attaching photos (e.g.
  // the edit-entry page's "add more photos" form), never on a form that also
  // collects other required fields (e.g. a new entry's title), where
  // submitting early would be premature.
  // translations: strings for the client-side EXIF-preview status message
  // and upload progress labels, passed as a JSON object from ERB (via
  // ApplicationHelper#photo_date_translations) since this controller has no
  // direct access to Rails' I18n.
  static values = { directUploadUrl: String, autoSubmit: Boolean, translations: Object }

  connect() {
    this.onPaste = this.onPaste.bind(this)
    this.element.addEventListener("paste", this.onPaste)
    this.defaultFileCountText = this.hasFileCountTarget ? this.fileCountTarget.textContent : null
    this.pendingUploads = 0
    // Rows currently showing a failure, rather than one sticky boolean - a
    // retried row that goes on to succeed needs to stop blocking autoSubmit
    // even though *some* upload in this batch failed at some point.
    this.failedRows = new Set()
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
    const t = this.translationsValue

    if (this.hasFileCountTarget) {
      this.fileCountTarget.textContent = files.length === 0
        ? this.defaultFileCountText
        : this.interpolate(files.length === 1 ? t.file_selected.one : t.file_selected.other, { count: files.length })
    }

    if (files.length === 0) {
      this.statusTarget.classList.add("hidden")
      return
    }

    this.uploadFiles(files)

    this.statusTarget.textContent = t.reading
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
      found.push(this.interpolate(t.found_date, { datetime: takenAt.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) }))
    } else {
      missing.push(t.date_word)
    }
    if (location) {
      found.push(t.found_location)
    } else {
      missing.push(t.location_word)
    }

    let message = found.length ? `${found.join(` ${t.and} `)} ${t.read_from_photos}` : ""
    if (missing.length) {
      const suffix = missing.length > 1 ? t.no_suffix.other : t.no_suffix.one
      message += `${message ? ` ${t.no_prefix}` : t.no_prefix} ${missing.join(` ${t.or} `)} ${suffix}`
    }
    this.statusTarget.textContent = message

    if (!takenAt && this.hasTimeCheckboxTarget && !this.timeCheckboxTarget.checked) {
      this.check(this.timeCheckboxTarget)
    }
    if (!location && this.hasLocationManualRadioTarget && !this.locationManualRadioTarget.checked) {
      this.check(this.locationManualRadioTarget)
    }
  }

  // Fills in %{name}-style placeholders, matching Rails' I18n interpolation
  // syntax, so translation strings can be authored the same way on both
  // sides instead of needing a separate JS-only templating convention.
  interpolate(template, params) {
    return template.replace(/%\{(\w+)\}/g, (_, key) => params[key])
  }

  uploadFiles(files) {
    if (!this.hasDirectUploadUrlValue || !this.hasUploadListTarget) return

    this.uploadListTarget.innerHTML = ""
    this.uploadListTarget.classList.remove("hidden")
    this.pendingUploads += files.length
    this.failedRows = new Set()
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
    this.attemptUpload(file, row)
  }

  // Re-attempts a single file into its existing row rather than building a
  // new one, so a batch where some files fail and some succeed doesn't
  // reshuffle or duplicate the list when the adventurer retries just the
  // failures - only pulled out of uploadFile so retryUpload can drive the
  // same DirectUpload flow into an already-failed row.
  //
  // Checks the file itself is a complete JPEG before spending any bandwidth
  // on it - a cloud photo library (iCloud/Google Photos "optimise storage")
  // can hand the browser a not-yet-fully-downloaded original, which direct
  // upload's checksum can't catch (it only verifies the bytes actually sent
  // arrived intact, not that they were the whole file to begin with). Server
  // still re-checks this (see Photo#acceptable_jpeg_completeness) as a
  // backstop for the plain-multipart fallback and anyone bypassing this JS.
  async attemptUpload(file, row) {
    if (!(await this.looksCompleteJpeg(file))) {
      this.finishUpload("Incomplete file: ran off the end of the file while scanning for the JPEG's end-of-image marker - it may not have fully downloaded before upload", null, file, row)
      return
    }

    const upload = new DirectUpload(file, this.directUploadUrlValue, {
      directUploadWillStoreFileWithXHR: (xhr) => {
        xhr.upload.addEventListener("progress", (event) => {
          if (!event.lengthComputable) return
          row.bar.style.width = `${Math.round((event.loaded / event.total) * 100)}%`
        })
      }
    })

    upload.create((error, blob) => this.finishUpload(error, blob, file, row))
  }

  // Whether the file decodes to a real FFD9 (End Of Image) marker before
  // running off the end of the buffer. Deliberately doesn't just check the
  // file's last two bytes - lots of complete, valid phone photos have data
  // *after* their real EOI on purpose (Android "Motion Photo" appends an MP4
  // clip; MPO/dual-camera files append a second whole JPEG), so that would
  // flag plenty of genuine, undamaged uploads as incomplete. Instead this
  // walks the marker structure to the entropy-coded scan data and scans
  // byte-by-byte from there respecting JPEG's escaping rules (a literal
  // 0xFF byte in scan data is always followed by 0x00; 0xFF followed by a
  // restart marker D0-D7 is a mid-scan checkpoint, not the end) - the same
  // thing a real decoder does, just without decoding any pixels. Only
  // meaningful for JPEG; other formats have their own container structure.
  async looksCompleteJpeg(file) {
    if (file.type !== "image/jpeg") return true

    const view = new DataView(await file.arrayBuffer())
    const length = view.byteLength
    if (length < 4 || view.getUint16(0) !== 0xffd8) return true // not a JPEG we can parse - let the server decide

    let i = 2
    while (i + 1 < length) {
      if (view.getUint8(i) !== 0xff) return false // expected a marker here - stream doesn't parse as JPEG

      const marker = view.getUint8(i + 1)
      if (marker === 0xd9) return true // EOI found before running off the end
      if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
        i += 2 // standalone marker with no payload (TEM, lone RSTn)
        continue
      }
      if (marker !== 0xda) {
        if (i + 4 > length) return false
        i += 2 + view.getUint16(i + 2) // skip this segment's declared payload
        continue
      }

      // SOS: skip its header, then scan the entropy-coded data byte by byte
      // until the next real marker (respecting the escaping rules above).
      i += 2 + view.getUint16(i + 2)
      while (i + 1 < length) {
        if (view.getUint8(i) === 0xff) {
          const next = view.getUint8(i + 1)
          if (next !== 0x00 && !(next >= 0xd0 && next <= 0xd7)) break
          i += 2
        } else {
          i += 1
        }
      }
    }
    return false // ran off the end of the file without ever finding an EOI
  }

  finishUpload(error, blob, file, row) {
    if (error) {
      this.failedRows.add(row)
      row.bar.classList.replace("bg-amber-600", "bg-red-600")
      row.label.textContent = this.interpolate(this.translationsValue.upload_failed, { filename: file.name, reason: this.uploadFailureReason(error) })
      row.label.title = error
      row.copy.classList.remove("hidden")
      row.retry.classList.remove("hidden")
      row.copy.onclick = () => this.copyErrorDetails(row.copy, file, error)
      row.retry.onclick = () => this.retryUpload(file, row)
    } else {
      // DirectUpload only calls back without an error once the server has
      // verified the uploaded bytes' checksum, so the full file is
      // confirmed intact by this point - safe to show the success tick.
      this.failedRows.delete(row)
      row.bar.style.width = "100%"
      row.bar.classList.remove("bg-amber-600", "bg-red-600")
      row.bar.classList.add("bg-green-600")
      row.check.classList.remove("hidden")
      row.copy.classList.add("hidden")
      row.retry.classList.add("hidden")
      const hidden = document.createElement("input")
      hidden.type = "hidden"
      hidden.name = "photo_signed_ids[]"
      hidden.value = blob.signed_id
      this.element.appendChild(hidden)
    }

    this.pendingUploads = Math.max(0, this.pendingUploads - 1)
    if (this.pendingUploads === 0) {
      this.setSubmitDisabled(false)
      if (this.autoSubmitValue && this.failedRows.size === 0) this.element.requestSubmit()
    }
  }

  retryUpload(file, row) {
    this.pendingUploads += 1
    this.setSubmitDisabled(true)
    row.bar.style.width = "0%"
    row.bar.classList.remove("bg-red-600", "bg-green-600")
    row.bar.classList.add("bg-amber-600")
    row.label.textContent = file.name
    row.label.removeAttribute("title")
    row.check.classList.add("hidden")
    row.copy.classList.add("hidden")
    row.retry.classList.add("hidden")
    this.attemptUpload(file, row)
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

    const check = document.createElement("span")
    check.className = "hidden text-green-600 dark:text-green-500 shrink-0"
    check.textContent = "✓"
    element.appendChild(check)

    // Only shown on failure - lets an adventurer copy the technical detail
    // (filename/size/type/status/timestamp, nothing account- or
    // server-specific) to paste into a support message, since the friendly
    // label text alone often isn't enough for us to diagnose a one-off
    // failure like a specific phone's oversized photos timing out.
    const copy = document.createElement("button")
    copy.type = "button"
    copy.className = "hidden shrink-0 text-stone-400 hover:text-stone-600 dark:hover:text-stone-200"
    copy.textContent = "📋"
    copy.title = this.translationsValue.copy_error
    element.appendChild(copy)

    // Also only shown on failure - retries just this one file (e.g. after a
    // dropped connection) without having to reselect every photo in the
    // batch, several of which may have already uploaded fine.
    const retry = document.createElement("button")
    retry.type = "button"
    retry.className = "hidden shrink-0 text-stone-400 hover:text-stone-600 dark:hover:text-stone-200"
    retry.textContent = "↻"
    retry.title = this.translationsValue.retry_upload
    element.appendChild(retry)

    return { element, label, bar, check, copy, retry }
  }

  // Maps the technical error DirectUpload reports (always English, e.g.
  // `Error storing "x.jpg". Status: 0`) to a short user-facing reason. The
  // full technical string is never discarded - it's still on the row's
  // title attribute and in the copy-to-clipboard details - this is just a
  // friendlier headline for the common cases.
  uploadFailureReason(error) {
    const t = this.translationsValue.upload_failed_reason
    if (error.startsWith("Incomplete file:")) return t.incomplete
    const status = Number(error.match(/Status: (\d+)/)?.[1])
    return status === 0 ? t.network : t.generic
  }

  async copyErrorDetails(button, file, error) {
    const details = [
      `File: ${file.name}`,
      `Size: ${(file.size / (1024 * 1024)).toFixed(1)} MB`,
      `Type: ${file.type || "unknown"}`,
      `Error: ${error}`,
      `Time: ${new Date().toISOString()}`,
      `Browser: ${navigator.userAgent}`
    ].join("\n")

    try {
      await navigator.clipboard.writeText(details)
      const original = button.textContent
      button.textContent = "✓"
      button.title = this.translationsValue.error_copied
      setTimeout(() => {
        button.textContent = original
        button.title = this.translationsValue.copy_error
      }, 1500)
    } catch {
      // Clipboard API unavailable (e.g. insecure context) - the technical
      // detail is still visible via the row's title attribute.
    }
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
    // `lat`/`lng` are 3-element [deg, min, sec] arrays when the tag parsed at
    // all, even if every component came out as 0 (e.g. a malformed rational
    // with a zero denominator, which readIfd maps to 0 rather than dropping
    // the tag) - checking truthiness alone treats that array as "found",
    // showing a location marker for what's actually the null-island (0,0)
    // non-value. Requiring at least one non-zero component avoids
    // misreporting "found location" for photos this preview can't actually
    // place on the map.
    if (!lat || !lng || (lat.every((v) => v === 0) && lng.every((v) => v === 0))) return null

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
