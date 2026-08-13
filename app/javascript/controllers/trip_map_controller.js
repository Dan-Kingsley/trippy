import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// Renders a Leaflet/OpenStreetMap map with one circular photo marker per
// located trip entry, connected in chronological order by a translucent
// line. The map's tiles repeat infinitely as the user pans east/west
// (Leaflet's default), so the markers/line are redrawn on every repeated
// "world copy" currently in view rather than just the one they were
// originally placed on - see #renderWorldCopies.
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

    // Unwrapped once and reused for the line, the markers, the bounds fit,
    // and every repeated world copy below - a trip that crosses the
    // antimeridian is only ~10s of km wide in reality, and all of those need
    // to agree it's a short hop near the 180/-180 seam rather than raw
    // coordinates ~358° apart, or the map would zoom out to fit "the whole
    // world" and strand the markers on opposite edges of the screen.
    this.entries = located
    this.latLngs = this.unwrapAntimeridian(located.map((e) => [ e.lat, e.lng ]))
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
  // keeps exactly one rendered copy of the trip's markers/line per offset,
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
    const shifted = this.latLngs.map(([ lat, lng ]) => [ lat, lng + shift ])

    if (shifted.length > 1) {
      L.polyline(shifted, { color: "#b45309", weight: 3, opacity: 0.75 }).addTo(layer)
    }

    this.entries.forEach((entry, i) => {
      const icon = L.divIcon({
        className: "trip-map-marker",
        html: `<a href="${entry.url}" class="block w-12 h-12 rounded-full border-2 border-white dark:border-stone-900 shadow-md overflow-hidden bg-stone-300 bg-cover bg-center" style="background-image:url('${entry.thumbnail_url || ""}')"></a>`,
        iconSize: [ 48, 48 ],
        iconAnchor: [ 24, 24 ]
      })
      L.marker(shifted[i], { icon, title: entry.title }).addTo(layer)
    })

    return layer
  }

  // Leaflet treats lat/lngs as plain numbers, so a trip that crosses the
  // antimeridian (e.g. from 179° to -179°, ~2° apart in reality) reads as
  // ~358° apart unless corrected - drawing the polyline the "long way"
  // around the globe, and blowing out fitBounds/marker placement to match.
  // Keeping each point's longitude continuous with the previous one
  // (letting it drift outside the normal -180..180 range as needed) fixes
  // all three at once - the map still renders it in the correct place since
  // longitudes just repeat every 360°.
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
