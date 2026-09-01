module ApplicationHelper
  # Renders a trip's cover image (explicit cover, or first entry's first photo)
  # as a variant, falling back to a placeholder icon when there's no photo yet.
  def trip_thumbnail_tag(trip, css_class: "")
    image = trip.cover_image
    if image&.attached?
      video = image.content_type&.start_with?("video/")
      image_tag video ? image.preview(resize_to_limit: [ 900, 900 ]) : image.variant(:thumb),
        class: css_class, loading: "lazy",
        data: { attachment_fallback: true, fallback_class: css_class, fallback_content: (video ? "🎬" : nil) }
    else
      content_tag :div, "🧭", class: "#{css_class} flex items-center justify-center text-4xl bg-stone-200 dark:bg-stone-800"
    end
  end

  # Renders a photo (or, for a video, its poster-frame preview with a play
  # icon overlay) sized to fill css_class's box. Variant/preview processing
  # happens lazily on first request to the image URL, not here, so a video
  # whose preview can't be generated (unsupported codec, ffmpeg unavailable)
  # surfaces as a failed image load - the attachment-fallback behavior in
  # application.js swaps that for a video-camera placeholder.
  def photo_thumb_tag(photo, size: 64, css_class: "")
    return unless photo.image.attached?

    inner_class = "w-full h-full object-cover"
    img = image_tag photo.video? ? photo.image.preview(resize_to_limit: [ size, size ]) : photo.image.variant(resize_to_fill: [ size, size ], saver: { quality: 80 }, loader: { fail_on: :none, unlimited: true }),
      class: inner_class, loading: "lazy",
      data: { attachment_fallback: true, fallback_class: inner_class, fallback_content: (photo.video? ? "🎬" : nil) }

    content_tag :div, class: "relative overflow-hidden #{css_class}" do
      photo.video? ? safe_join([ img, video_play_icon ]) : img
    end
  end

  def video_play_icon(size: "w-8 h-8 text-sm")
    content_tag :div, class: "pointer-events-none absolute inset-0 flex items-center justify-center" do
      content_tag :div, "▶", class: "bg-black/50 text-white rounded-full flex items-center justify-center pl-0.5 #{size}"
    end
  end

  # Renders a user's profile picture as a variant, falling back to a circle
  # with their initial when they haven't uploaded one.
  def avatar_tag(user, size: 64, css_class: "")
    return "" unless user

    base_class = "rounded-full object-cover shrink-0 #{css_class}"
    if user.profile_picture.attached?
      image_tag user.profile_picture.variant(:thumb),
        class: base_class, loading: "lazy", alt: user.username, title: user.username,
        data: { attachment_fallback: true, fallback_class: base_class, fallback_content: user.username.first.upcase }
    else
      content_tag :div, user.username.first.upcase,
        class: "#{base_class} bg-stone-300 dark:bg-stone-700 text-stone-700 dark:text-stone-200 flex items-center justify-center font-medium",
        title: user.username
    end
  end

  # A small notification dot marking an entry as unread (solid) or stale -
  # seen before, but edited since (half-filled, via an SVG arc rather than a
  # CSS split so it renders as a crisp semicircle at any size). `read` is the
  # viewer's TripEntryRead for this entry, or nil - see
  # TripsController#show, which preloads these to avoid an N+1 across a
  # whole page of entries, and TripEntry#unread_state.
  def unread_dot_tag(entry, read)
    return "" unless Current.user

    state = entry.unread_state(read)
    return "" unless state

    title = t("trips.show.#{state == :unread ? "unread_entry" : "stale_entry"}")
    fill = "fill-red-600 dark:fill-red-500"

    inner = content_tag(:title, title) +
      content_tag(:circle, "", cx: 4, cy: 4, r: 3.5, class: "fill-white dark:fill-stone-900")

    inner += if state == :unread
      content_tag(:circle, "", cx: 4, cy: 4, r: 2.75, class: fill)
    else
      content_tag(:path, "", d: "M4 1.25 A2.75 2.75 0 0 1 4 6.75 Z", class: fill) +
        content_tag(:circle, "", cx: 4, cy: 4, r: 2.75, class: "fill-none stroke-red-600 dark:stroke-red-500", "stroke-width": 0.6)
    end

    content_tag :svg, inner, viewBox: "0 0 8 8", class: "absolute -top-1.5 -left-1.5 w-3.5 h-3.5 drop-shadow", role: "img"
  end

  # Formats a trip's entry date span, e.g. "12-18 Jan 2026", collapsing to a
  # single date when a trip's entries all happened on the same day.
  def trip_date_range_text(trip)
    range = trip.entry_date_range
    return nil unless range

    first, last = range.map(&:to_date)
    return l(first, format: :trippy_short) if first == last

    if first.year == last.year && first.month == last.month
      "#{first.strftime('%-d')}-#{l(last, format: :trippy_short)}"
    elsif first.year == last.year
      "#{l(first, format: :trippy_day_month)} - #{l(last, format: :trippy_short)}"
    else
      "#{l(first, format: :trippy_short)} - #{l(last, format: :trippy_short)}"
    end
  end

  # Builds the translated strings the photo-date Stimulus controller needs
  # for its client-side EXIF-preview status message and upload progress
  # labels, passed down as a JSON data value since JS has no direct access
  # to Rails i18n.
  def photo_date_translations
    t("javascript.photo_date")
  end

  # Thumbnail URL for a trip-map marker popup. Videos have no :thumb image
  # variant (that's an image-only transform) - use their poster preview
  # instead.
  def map_thumbnail_url(photo)
    return nil unless photo&.image&.attached?

    url_for(photo.video? ? photo.image.preview(resize_to_limit: [ 900, 900 ]) : photo.image.variant(:thumb))
  end

  def render_markdown(text)
    return "" if text.blank?
    renderer = Redcarpet::Render::HTML.new(filter_html: true, safe_links_only: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, strikethrough: true)
    sanitize markdown.render(text), tags: %w[p br strong em a ul ol li blockquote code pre h1 h2 h3 h4 img table thead tbody tr th td del],
      attributes: %w[href src alt title]
  end
end
