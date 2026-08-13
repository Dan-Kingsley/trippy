import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

const LINE_COLOR = "#b45309"
const LINE_WEIGHT = 3
const LINE_OPACITY = 0.75
const CURVE_STEPS_PER_SEGMENT = 24 // vertices sampled along each entry-to-entry great-circle arc
const ARROW_ARM_LENGTH = LINE_WEIGHT * 4
const ARROW_HALF_ANGLE_DEGREES = 25

// Renders a Leaflet/OpenStreetMap map with one circular photo marker per
// located trip entry, connected in chronological order by a translucent
// great-circle route (curved to follow the Earth's surface rather than
// cutting a straight line through it) with a directional arrow at the
// midpoint of each leg. The map's tiles repeat infinitely as the user pans
// east/west (Leaflet's default), so the markers/route are redrawn on every
// repeated "world copy" currently in view rather than just the one they
// were originally placed on - see #renderWorldCopies.
export default class extends Controller {
  static values = { entries: Array }

  connect() {
    const located = this.entriesValue.filter((e) => e.lat != null && e.lng != null)

    this.map = L.map(this.element, { scrollWheelZoom: false })
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
    this.curvePoints = this.buildCurve(this.latLngs)
    this.segments = this.buildSegments(this.latLngs)
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

    if (this.curvePoints.length > 1) {
      const shiftedCurve = this.curvePoints.map(([ lat, lng ]) => [ lat, lng + shift ])
      L.polyline(shiftedCurve, { color: LINE_COLOR, weight: LINE_WEIGHT, opacity: LINE_OPACITY }).addTo(layer)
    }

    this.segments.forEach(({ lat, lng, bearing }) => {
      L.marker([ lat, lng + shift ], {
        icon: this.buildArrowIcon(bearing),
        interactive: false,
        keyboard: false
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
      L.marker(shiftedEntries[i], { icon, title: entry.title }).addTo(layer)
    })

    return layer
  }

  // A two-stroke chevron (matching the route line's color, width and
  // opacity so it reads as part of the line rather than a separate marker),
  // rotated in CSS to point along the direction of travel. Sized in screen
  // pixels via divIcon, so - like the route's stroke-width - it stays the
  // same visual size regardless of zoom level.
  buildArrowIcon(bearingDegrees) {
    const angle = (ARROW_HALF_ANGLE_DEGREES * Math.PI) / 180
    const dx = ARROW_ARM_LENGTH * Math.sin(angle)
    const dy = ARROW_ARM_LENGTH * Math.cos(angle)
    const half = Math.ceil(Math.max(dx, dy)) + 2

    return L.divIcon({
      className: "trip-map-arrow",
      html: `<svg width="${half * 2}" height="${half * 2}" viewBox="${-half} ${-half} ${half * 2} ${half * 2}"
                  style="transform: rotate(${bearingDegrees}deg)">
               <line x1="0" y1="0" x2="${dx.toFixed(2)}" y2="${dy.toFixed(2)}"
                     stroke="${LINE_COLOR}" stroke-opacity="${LINE_OPACITY}" stroke-width="${LINE_WEIGHT}" stroke-linecap="round" />
               <line x1="0" y1="0" x2="${(-dx).toFixed(2)}" y2="${dy.toFixed(2)}"
                     stroke="${LINE_COLOR}" stroke-opacity="${LINE_OPACITY}" stroke-width="${LINE_WEIGHT}" stroke-linecap="round" />
             </svg>`,
      iconSize: [ half * 2, half * 2 ],
      iconAnchor: [ half, half ]
    })
  }

  // One directional arrow per consecutive pair of entries, placed exactly on
  // the great-circle route at that leg's midpoint (t=0.5 along #slerp, which
  // is also one of the vertices #buildCurve samples - so it can't drift off
  // the rendered line the way a plain lat/lng average could) and rotated to
  // the route's tangent bearing there, pointing from the older entry toward
  // the newer one.
  buildSegments(latLngs) {
    const segments = []
    for (let i = 1; i < latLngs.length; i++) {
      const p1 = latLngs[i - 1]
      const p2 = latLngs[i]
      const [ lat, lng ] = this.slerp(p1, p2, 0.5)

      // The tangent direction at the midpoint, approximated from two points
      // just either side of it - a great circle's bearing changes along its
      // length (except along the equator/a meridian), so the leg's start
      // bearing isn't generally the same as its midpoint bearing.
      const before = this.slerp(p1, p2, 0.49)
      const after = this.slerp(p1, p2, 0.51)

      segments.push({ lat, lng, bearing: this.bearingBetween(before[0], before[1], after[0], after[1]) })
    }
    return segments
  }

  // Samples each entry-to-entry leg as a great-circle arc (via #slerp)
  // rather than a straight lat/lng line, so the route drawn on the map
  // curves the way it actually would over the Earth's surface. Points are
  // concatenated leg by leg (skipping each leg's start, since it's the same
  // point as the previous leg's end) into one continuous curve.
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
