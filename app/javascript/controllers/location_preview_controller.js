import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// A small, non-interactive map used to preview where an entry's location
// will be set to - the automatic mean of its photos' GPS data, or whichever
// photo's location is currently selected - before the adventurer commits to
// that choice. Contrast with location-picker, which is for manually
// dragging to set a location.
export default class extends Controller {
  static targets = [ "map" ]
  static values = { lat: Number, lng: Number }

  connect() {
    this.map = L.map(this.mapTarget, {
      zoomControl: false, dragging: false, scrollWheelZoom: false,
      doubleClickZoom: false, boxZoom: false, keyboard: false, touchZoom: false
    }).setView([ this.latValue, this.lngValue ], 11)

    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19
    }).addTo(this.map)

    this.marker = L.marker([ this.latValue, this.lngValue ]).addTo(this.map)

    // Same rationale as location-picker: a panel that starts hidden (e.g.
    // the "photo" option before it's selected) is measured with a
    // zero-sized container unless re-measured once it's actually shown.
    this.resizeObserver = new ResizeObserver(() => this.map.invalidateSize())
    this.resizeObserver.observe(this.mapTarget)
  }

  // Called when the adventurer clicks a different photo's thumbnail in the
  // "use one of your photos' locations" panel, via each radio's data-lat/lng.
  showPhoto({ target }) {
    const lat = parseFloat(target.dataset.lat)
    const lng = parseFloat(target.dataset.lng)
    if (Number.isNaN(lat) || Number.isNaN(lng)) return

    this.map.panTo([ lat, lng ])
    this.marker.setLatLng([ lat, lng ])
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.map?.remove()
  }
}
