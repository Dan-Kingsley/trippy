// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

// Any <img> opted in via data-attachment-fallback (avatars, photo/cover
// thumbnails) gets swapped for a plain placeholder box instead of the
// browser's native broken-image icon if it fails to load - whether that's
// an expired/failed request, a corrupt upload that never processed into a
// usable variant, or a dropped connection. "error" doesn't bubble, so this
// has to listen on the capture phase to catch it via delegation.
document.addEventListener("error", (event) => {
  const img = event.target
  if (!(img instanceof HTMLImageElement) || img.dataset.attachmentFallback === undefined) return
  if (img.dataset.fallbackApplied) return
  img.dataset.fallbackApplied = "true"

  const placeholder = document.createElement("div")
  placeholder.className = `${img.dataset.fallbackClass || img.className} flex items-center justify-center bg-stone-200 dark:bg-stone-800 text-stone-400 dark:text-stone-500`
  placeholder.textContent = img.dataset.fallbackContent || "🖼️"
  img.replaceWith(placeholder)
}, true)
