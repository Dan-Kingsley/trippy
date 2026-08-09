import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// Lets an adventurer set a location by dragging a map under a fixed centre
// pin, instead of typing raw coordinates. The latitude/longitude fields stay
// in the DOM (read-only) so the rest of the form keeps working unchanged.
export default class extends Controller {
  static targets = [ "map", "lat", "lng" ]
  static values = { lat: Number, lng: Number }

  connect() {
    const located = this.hasLatValue && this.hasLngValue
    const center = located ? [ this.latValue, this.lngValue ] : [ 20, 0 ]

    this.map = L.map(this.mapTarget, { scrollWheelZoom: false }).setView(center, located ? 13 : 2)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19
    }).addTo(this.map)

    this.updateCoordinates()
    this.map.on("move", () => this.updateCoordinates())
  }

  // Called (after toggle#sync) when the "manually set location" checkbox
  // changes, so the map is measured/redrawn correctly once it's unhidden.
  sync() {
    requestAnimationFrame(() => {
      this.map.invalidateSize()
      this.updateCoordinates()
    })
  }

  updateCoordinates() {
    const { lat, lng } = this.map.getCenter()
    this.latTarget.value = lat.toFixed(6)
    this.lngTarget.value = lng.toFixed(6)
  }

  disconnect() {
    this.map?.remove()
  }
}
