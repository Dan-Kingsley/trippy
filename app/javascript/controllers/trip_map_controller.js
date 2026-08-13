import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// Renders a Leaflet/OpenStreetMap map with one circular photo marker per
// located trip entry, connected in chronological order by a translucent line.
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

    // Unwrapped once and reused for the line, the markers, and the bounds
    // fit below - a trip that crosses the antimeridian is only ~10s of km
    // wide in reality, and all three need to agree it's a short hop near
    // the 180/-180 seam rather than raw coordinates ~358° apart, or the map
    // would zoom out to fit "the whole world" and strand the markers on
    // opposite edges of the screen.
    const latLngs = this.unwrapAntimeridian(located.map((e) => [ e.lat, e.lng ]))

    if (located.length > 1) {
      L.polyline(latLngs, { color: "#b45309", weight: 3, opacity: 0.75 }).addTo(this.map)
    }

    located.forEach((entry, i) => {
      const icon = L.divIcon({
        className: "trip-map-marker",
        html: `<a href="${entry.url}" class="block w-12 h-12 rounded-full border-2 border-white dark:border-stone-900 shadow-md overflow-hidden bg-stone-300 bg-cover bg-center" style="background-image:url('${entry.thumbnail_url || ""}')"></a>`,
        iconSize: [ 48, 48 ],
        iconAnchor: [ 24, 24 ]
      })
      L.marker(latLngs[i], { icon, title: entry.title }).addTo(this.map)
    })

    // Capped below their "natural" zoom so the initial view stays more
    // zoomed out; the user can always zoom in further from here.
    if (located.length === 1) {
      this.map.setView(latLngs[0], 10)
    } else {
      this.map.fitBounds(latLngs, { padding: [ 40, 40 ], maxZoom: 10 })
    }
  }

  disconnect() {
    this.map?.remove()
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
