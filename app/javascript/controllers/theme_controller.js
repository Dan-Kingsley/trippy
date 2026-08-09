import { Controller } from "@hotwired/stimulus"

// Toggles light/dark mode by adding/removing .dark on <html>, persisted in localStorage.
// A tiny inline script in the layout <head> applies the stored preference before first paint.
export default class extends Controller {
  static targets = ["lightIcon", "darkIcon"]

  connect() {
    this.refreshIcons()
  }

  toggle() {
    const root = document.documentElement
    const isDark = root.classList.toggle("dark")
    localStorage.setItem("trippy-theme", isDark ? "dark" : "light")
    this.refreshIcons()
  }

  refreshIcons() {
    const isDark = document.documentElement.classList.contains("dark")
    this.lightIconTargets.forEach((el) => el.classList.toggle("hidden", isDark))
    this.darkIconTargets.forEach((el) => el.classList.toggle("hidden", !isDark))
  }
}
