import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

const FULL_GROUP_COLOR = "#b45309" // used only when every trip collaborator was present at both ends of a segment
const LINE_WEIGHT = 3
const LINE_OPACITY = 0.75
const CURVE_STEPS_PER_SEGMENT = 24 // vertices sampled along each entry-to-entry great-circle arc
const ARROW_ARM_LENGTH = LINE_WEIGHT * 4
const ARROW_HALF_ANGLE_DEGREES = 25
const BASE_PANE_Z_INDEX = 401 // just above the overlay-pane (400), and below every built-in Leaflet pane

// The traditional artist's RYB color wheel's 6 primary/secondary stops, each
// given as a pigment-mixing (r, y, b) coordinate rather than a displayed RGB
// color - see #rybToHex. Adjacent stops are complementary pairs exactly
// where artists expect them (red/green, yellow/violet, blue/orange).
const WHEEL_CORNERS = [
  { r: 1, y: 0, b: 0 }, // red
  { r: 1, y: 1, b: 0 }, // orange
  { r: 0, y: 1, b: 0 }, // yellow
  { r: 0, y: 1, b: 1 }, // green
  { r: 0, y: 0, b: 1 }, // blue
  { r: 1, y: 0, b: 1 } // violet
]

// The 8 corners of the RYB pigment-mixing cube, each mapped to the RGB color
// it actually looks like - the classic Gossett & Chen "paint mixing" model.
// Trilinearly interpolating between these (see #rybToHex) is what makes
// mixed pigment coordinates behave like real paint instead of RGB light
// (blue+yellow -> green, red+green -> muddy brown, not grey/white).
const RYB_CUBE_CORNERS = {
  white: [ 1, 1, 1 ],
  red: [ 1, 0, 0 ],
  yellow: [ 1, 1, 0 ],
  blue: [ 0.163, 0.373, 0.6 ],
  orange: [ 1, 0.5, 0 ],
  violet: [ 0.5, 0, 0.5 ],
  green: [ 0, 0.66, 0.2 ],
  black: [ 0.2, 0.094, 0 ]
}

// Renders a Leaflet/OpenStreetMap map with one circular photo marker per
// located trip entry, connected by great-circle routes (curved to follow the
// Earth's surface rather than cutting a straight line through it) with a
// directional arrow at the midpoint of each one. The map's tiles repeat
// infinitely as the user pans east/west (Leaflet's default), so the
// markers/route are redrawn on every repeated "world copy" currently in view
// rather than just the one they were originally placed on - see
// #renderWorldCopies.
//
// Rather than one line per consecutive pair of entries, each trip
// collaborator gets their own chronological "presence thread" through only
// the entries they were tagged at - skipping over entries they weren't
// present for, and reconnecting directly to the next one they were. Where
// multiple collaborators' threads travel between the same two entries, they
// share a single rendered line, colored by mixing those collaborators'
// colors together (or a fixed brown, when the whole trip's collaborator list
// overlaps) - see #buildSegments.
//
// Entries arrive pre-sorted oldest-to-newest. Rather than leaning on
// Leaflet's default marker stacking (which is based on on-screen pixel
// position), each entry and each segment gets its own dedicated pane with an
// explicit z-index, so stacking always reflects chronology instead of screen
// geometry: later entries render above earlier ones, and each segment's
// line/arrow renders directly beneath the older (the "from") entry it
// connects - see #createPanes.
export default class extends Controller {
  static values = { entries: Array, collaboratorIds: Array }

  connect() {
    const located = this.entriesValue.filter((e) => e.lat != null && e.lng != null)

    this.map = L.map(this.element, { scrollWheelZoom: true })
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19
    }).addTo(this.map)

    if (located.length === 0) {
      this.map.setView([20, 0], 2)
      return
    }

    // Unwrapped once and reused for the route, the markers, the bounds fit,
    // and every repeated world copy below - a trip that crosses the
    // antimeridian is only ~10s of km wide in reality, and all of those need
    // to agree it's a short hop near the 180/-180 seam rather than raw
    // coordinates ~358° apart, or the map would zoom out to fit "the whole
    // world" and strand the markers on opposite edges of the screen.
    this.entries = located
    this.latLngs = this.unwrapAntimeridian(located.map((e) => [ e.lat, e.lng ]))
    this.segments = this.buildSegments()
    this.createPanes()
    this.worldCopies = new Map()

    // Capped below their "natural" zoom so the initial view stays more
    // zoomed out; the user can always zoom in further from here.
    if (located.length === 1) {
      this.map.setView(this.latLngs[0], 10)
    } else {
      this.map.fitBounds(this.latLngs, { padding: [ 40, 40 ], maxZoom: 10 })
    }

    this.renderWorldCopies()
    this.map.on("moveend", this.renderWorldCopies)
  }

  disconnect() {
    this.map?.remove()
  }

  // Leaflet's tiles wrap seamlessly past +/-180°, but vector layers
  // (markers, polylines) only ever render at the one coordinate they were
  // given - they don't automatically reappear on every repeated world copy
  // the way tiles do. Whenever the view settles, this works out which
  // whole-world offsets (…, -360°, 0°, +360°, …) are currently visible and
  // keeps exactly one rendered copy of the trip's markers/route per offset,
  // so the trip shows up on whatever copy of the world the user has panned
  // to, not just the one it was originally drawn on.
  renderWorldCopies = () => {
    const EDGE_BUFFER_DEGREES = 10 // avoids markers popping in/out right at the viewport edge

    const bounds = this.map.getBounds()
    const lngs = this.latLngs.map(([ , lng ]) => lng)
    const centerLng = (Math.min(...lngs) + Math.max(...lngs)) / 2
    const spread = Math.max(...lngs) - Math.min(...lngs)

    const minOffset = Math.floor((bounds.getWest() - spread - centerLng - EDGE_BUFFER_DEGREES) / 360)
    const maxOffset = Math.ceil((bounds.getEast() + spread - centerLng + EDGE_BUFFER_DEGREES) / 360)

    for (const [ offset, layer ] of this.worldCopies) {
      if (offset < minOffset || offset > maxOffset) {
        layer.remove()
        this.worldCopies.delete(offset)
      }
    }

    for (let offset = minOffset; offset <= maxOffset; offset++) {
      if (this.worldCopies.has(offset)) continue
      this.worldCopies.set(offset, this.buildWorldCopy(offset * 360).addTo(this.map))
    }
  }

  buildWorldCopy(shift) {
    const layer = L.layerGroup()

    this.segments.forEach((segment, i) => {
      const pane = this.segmentPaneNames[i]

      if (segment.curve.length > 1) {
        const shiftedCurve = segment.curve.map(([ lat, lng ]) => [ lat, lng + shift ])
        L.polyline(shiftedCurve, { color: segment.color, weight: LINE_WEIGHT, opacity: LINE_OPACITY, pane }).addTo(layer)
      }

      L.marker([ segment.arrow.lat, segment.arrow.lng + shift ], {
        icon: this.buildArrowIcon(segment.arrow.bearing, segment.color),
        interactive: false,
        keyboard: false,
        pane
      }).addTo(layer)
    })

    const shiftedEntries = this.latLngs.map(([ lat, lng ]) => [ lat, lng + shift ])
    this.entries.forEach((entry, i) => {
      const icon = L.divIcon({
        className: "trip-map-marker",
        html: `<a href="${entry.url}" class="block w-12 h-12 rounded-full border-2 border-white dark:border-stone-900 shadow-md overflow-hidden bg-stone-300 bg-cover bg-center" style="background-image:url('${entry.thumbnail_url || ""}')"></a>`,
        iconSize: [ 48, 48 ],
        iconAnchor: [ 24, 24 ]
      })
      L.marker(shiftedEntries[i], { icon, title: entry.title, pane: this.entryPaneNames[i] }).addTo(layer)
    })

    return layer
  }

  // One dedicated Leaflet pane per entry and per segment, so stacking order
  // is driven entirely by explicit z-index rather than Leaflet's default
  // (on-screen pixel position). This.segments is sorted by (from, to), so
  // walking entries in order and, at each one, draining every segment whose
  // "from" is that entry reproduces the original interleaving - segment(0,1),
  // entry 0, segment(1,2), entry 1, ... - generalized to handle multiple
  // segments (or none) sharing the same "from", including ones that skip
  // ahead to a non-adjacent "to". Each segment sits directly beneath the
  // older ("from") entry it starts at, and every entry outranks every entry
  // before it.
  createPanes() {
    this.segmentPaneNames = []
    this.entryPaneNames = []

    let z = BASE_PANE_Z_INDEX
    let nextSegment = 0
    this.entries.forEach((_, i) => {
      while (nextSegment < this.segments.length && this.segments[nextSegment].from === i) {
        const segmentPane = `trip-map-segment-pane-${nextSegment}`
        this.map.createPane(segmentPane).style.zIndex = z++
        this.segmentPaneNames.push(segmentPane)
        nextSegment++
      }

      const entryPane = `trip-map-entry-pane-${i}`
      this.map.createPane(entryPane).style.zIndex = z++
      this.entryPaneNames.push(entryPane)
    })
  }

  // A two-stroke chevron (matching the route line's color, width and
  // opacity so it reads as part of the line rather than a separate marker),
  // rotated in CSS to point along the direction of travel. Sized in screen
  // pixels via divIcon, so - like the route's stroke-width - it stays the
  // same visual size regardless of zoom level.
  buildArrowIcon(bearingDegrees, color) {
    const angle = (ARROW_HALF_ANGLE_DEGREES * Math.PI) / 180
    const dx = ARROW_ARM_LENGTH * Math.sin(angle)
    const dy = ARROW_ARM_LENGTH * Math.cos(angle)
    const half = Math.ceil(Math.max(dx, dy)) + 2

    return L.divIcon({
      className: "trip-map-arrow",
      html: `<svg width="${half * 2}" height="${half * 2}" viewBox="${-half} ${-half} ${half * 2} ${half * 2}"
                  style="transform: rotate(${bearingDegrees}deg)">
               <line x1="0" y1="0" x2="${dx.toFixed(2)}" y2="${dy.toFixed(2)}"
                     stroke="${color}" stroke-opacity="${LINE_OPACITY}" stroke-width="${LINE_WEIGHT}" stroke-linecap="round" />
               <line x1="0" y1="0" x2="${(-dx).toFixed(2)}" y2="${dy.toFixed(2)}"
                     stroke="${color}" stroke-opacity="${LINE_OPACITY}" stroke-width="${LINE_WEIGHT}" stroke-linecap="round" />
             </svg>`,
      iconSize: [ half * 2, half * 2 ],
      iconAnchor: [ half, half ]
    })
  }

  // Every trip collaborator (owner first, then the rest in the stable order
  // the server sent) walks their own chronological "presence thread" -
  // just the located entries they were tagged at, skipping any they weren't
  // - and each consecutive pair along that thread is a candidate segment.
  // Candidate segments sharing the same (from, to) entries - because two or
  // more collaborators' threads both happen to hop between the same pair -
  // are merged into a single rendered segment, colored by mixing every
  // contributing collaborator's color together (see #segmentColor). Sorted
  // by (from, to) so #createPanes can walk it in lockstep with the entries.
  buildSegments() {
    const total = this.collaboratorIdsValue.length
    const coordinates = new Map(this.collaboratorIdsValue.map((id, i) => [ id, this.wheelCoordinate(i, total) ]))

    const grouped = new Map()
    this.collaboratorIdsValue.forEach((id) => {
      const path = []
      this.entries.forEach((entry, i) => {
        if (entry.participant_ids?.includes(id)) path.push(i)
      })

      for (let t = 1; t < path.length; t++) {
        const from = path[t - 1]
        const to = path[t]
        const key = `${from}-${to}`
        if (!grouped.has(key)) grouped.set(key, { from, to, contributors: new Set() })
        grouped.get(key).contributors.add(id)
      }
    })

    return [ ...grouped.values() ]
      .sort((a, b) => a.from - b.from || a.to - b.to)
      .map(({ from, to, contributors }) => this.buildSegment(from, to, [ ...contributors ], total, coordinates))
  }

  // A single segment's geometry (curve + midpoint arrow, exactly as legs
  // were built previously - #buildCurve/#slerp/#bearingBetween don't care
  // whether "from" and "to" are adjacent entries or a multi-entry skip) plus
  // its color: the fixed brown constant when every one of the trip's
  // collaborators contributed to this segment, otherwise the RYB mix of just
  // the contributors' colors (a "mix" of one collaborator is just their own
  // color, so lone contributors fall out of the same formula for free).
  buildSegment(from, to, contributorIds, total, coordinates) {
    const p1 = this.latLngs[from]
    const p2 = this.latLngs[to]
    const [ lat, lng ] = this.slerp(p1, p2, 0.5)

    // The tangent direction at the midpoint, approximated from two points
    // just either side of it - a great circle's bearing changes along its
    // length (except along the equator/a meridian), so a segment's start
    // bearing isn't generally the same as its midpoint bearing.
    const before = this.slerp(p1, p2, 0.49)
    const after = this.slerp(p1, p2, 0.51)
    const bearing = this.bearingBetween(before[0], before[1], after[0], after[1])

    const color = contributorIds.length === total
      ? FULL_GROUP_COLOR
      : this.rybToHex(this.mixRyb(contributorIds.map((id) => coordinates.get(id))))

    return { from, to, color, curve: this.buildCurve([ p1, p2 ]), arrow: { lat, lng, bearing } }
  }

  // The collaborator at `index` of `total`'s position on the 6-stop RYB
  // wheel, spaced evenly around it (`index * 6 / total`). Landing exactly on
  // a corner when 6/total is a whole number (e.g. total=2 -> red & green,
  // total=3 -> red, yellow & blue - the RYB primary triad); otherwise
  // interpolated between the two nearest corners.
  wheelCoordinate(index, total) {
    const position = (index * WHEEL_CORNERS.length) / total
    const lower = Math.floor(position) % WHEEL_CORNERS.length
    const upper = (lower + 1) % WHEEL_CORNERS.length
    const frac = position - Math.floor(position)

    const a = WHEEL_CORNERS[lower]
    const b = WHEEL_CORNERS[upper]
    return {
      r: a.r + (b.r - a.r) * frac,
      y: a.y + (b.y - a.y) * frac,
      b: a.b + (b.b - a.b) * frac
    }
  }

  // Mixing pigments = averaging their (r, y, b) mixing coordinates (not
  // their displayed RGB colors), the same way a paint-mixing simulator
  // would - see #rybToHex for why that produces realistic blends.
  mixRyb(coordinates) {
    const sum = coordinates.reduce((acc, c) => ({ r: acc.r + c.r, y: acc.y + c.y, b: acc.b + c.b }), { r: 0, y: 0, b: 0 })
    const n = coordinates.length
    return { r: sum.r / n, y: sum.y / n, b: sum.b / n }
  }

  // Converts an (r, y, b) pigment-mixing coordinate to a displayable hex
  // color via trilinear interpolation between the 8 corners of the RYB cube
  // (see RYB_CUBE_CORNERS) - the standard way to render/mix colors in RYB
  // pigment space rather than RGB light space.
  rybToHex({ r, y, b }) {
    const { white, red, yellow, blue, orange, violet, green, black } = RYB_CUBE_CORNERS

    const channel = (i) =>
      (1 - r) * (1 - y) * (1 - b) * white[i] +
      r * (1 - y) * (1 - b) * red[i] +
      (1 - r) * y * (1 - b) * yellow[i] +
      (1 - r) * (1 - y) * b * blue[i] +
      r * y * (1 - b) * orange[i] +
      r * (1 - y) * b * violet[i] +
      (1 - r) * y * b * green[i] +
      r * y * b * black[i]

    const toHex = (v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")
    return `#${toHex(channel(0))}${toHex(channel(1))}${toHex(channel(2))}`
  }

  // Samples an entry-to-entry leg as a great-circle arc (via #slerp) rather
  // than a straight lat/lng line, so the route drawn on the map curves the
  // way it actually would over the Earth's surface.
  buildCurve(latLngs) {
    const points = [ latLngs[0] ]
    for (let i = 1; i < latLngs.length; i++) {
      for (let step = 1; step <= CURVE_STEPS_PER_SEGMENT; step++) {
        points.push(this.slerp(latLngs[i - 1], latLngs[i], step / CURVE_STEPS_PER_SEGMENT))
      }
    }
    return points
  }

  // Spherical linear interpolation: the point a fraction `f` of the way
  // along the great-circle arc from p1 to p2 (f=0 -> p1, f=1 -> p2),
  // computed via 3D unit vectors so it follows the Earth's curvature
  // instead of a straight line between the two lat/lngs.
  slerp([ lat1, lng1 ], [ lat2, lng2 ], f) {
    const toRad = (d) => (d * Math.PI) / 180
    const toDeg = (r) => (r * 180) / Math.PI

    const v1 = this.toCartesian(toRad(lat1), toRad(lng1))
    const v2 = this.toCartesian(toRad(lat2), toRad(lng2))

    const dot = Math.max(-1, Math.min(1, v1.x * v2.x + v1.y * v2.y + v1.z * v2.z))
    const theta = Math.acos(dot)

    if (theta < 1e-9) return [ lat1, lng1 ]

    const a = Math.sin((1 - f) * theta) / Math.sin(theta)
    const b = Math.sin(f * theta) / Math.sin(theta)

    const x = a * v1.x + b * v2.x
    const y = a * v1.y + b * v2.y
    const z = a * v1.z + b * v2.z

    const lat = toDeg(Math.atan2(z, Math.sqrt(x * x + y * y)))
    let lng = toDeg(Math.atan2(y, x))

    // Keep the interpolated point continuous with this leg's start, so it
    // doesn't jump to the other side of the +/-180 seam mid-curve.
    while (lng - lng1 > 180) lng -= 360
    while (lng - lng1 < -180) lng += 360

    return [ lat, lng ]
  }

  toCartesian(latRad, lngRad) {
    return {
      x: Math.cos(latRad) * Math.cos(lngRad),
      y: Math.cos(latRad) * Math.sin(lngRad),
      z: Math.sin(latRad)
    }
  }

  // Initial compass bearing (0deg = north, 90deg = east) from one point to
  // another. Used both for the arrow rotation above and, since Mercator is
  // a conformal (angle-preserving) projection, this geographic bearing
  // matches the on-screen rotation needed to align the arrow with the
  // rendered curve without any separate pixel-space math.
  bearingBetween(lat1, lng1, lat2, lng2) {
    const toRad = (deg) => (deg * Math.PI) / 180
    const toDeg = (rad) => (rad * 180) / Math.PI
    const phi1 = toRad(lat1)
    const phi2 = toRad(lat2)
    const deltaLng = toRad(lng2 - lng1)

    const y = Math.sin(deltaLng) * Math.cos(phi2)
    const x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(deltaLng)

    return (toDeg(Math.atan2(y, x)) + 360) % 360
  }

  // Leaflet treats lat/lngs as plain numbers, so a trip that crosses the
  // antimeridian (e.g. from 179° to -179°, ~2° apart in reality) reads as
  // ~358° apart unless corrected - drawing the route the "long way" around
  // the globe, and blowing out fitBounds/marker placement to match. Keeping
  // each point's longitude continuous with the previous one (letting it
  // drift outside the normal -180..180 range as needed) fixes all three at
  // once - the map still renders it in the correct place since longitudes
  // just repeat every 360°.
  unwrapAntimeridian(latLngs) {
    const unwrapped = [ latLngs[0] ]

    for (let i = 1; i < latLngs.length; i++) {
      const [ lat, lng ] = latLngs[i]
      const prevLng = unwrapped[i - 1][1]
      let adjusted = lng
      while (adjusted - prevLng > 180) adjusted -= 360
      while (adjusted - prevLng < -180) adjusted += 360
      unwrapped.push([ lat, adjusted ])
    }

    return unwrapped
  }
}
