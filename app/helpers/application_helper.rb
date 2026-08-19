module ApplicationHelper
  # Renders a trip's cover image (explicit cover, or first entry's first photo)
  # as a variant, falling back to a placeholder icon when there's no photo yet.
  def trip_thumbnail_tag(trip, css_class: "")
    image = trip.cover_image
    if image&.attached?
      image_tag image.variant(resize_to_fill: [ 600, 400 ], saver: { quality: 80 }),
        class: css_class, loading: "lazy"
    else
      content_tag :div, "🧭", class: "#{css_class} flex items-center justify-center text-4xl bg-stone-200 dark:bg-stone-800"
    end
  end

  def photo_thumb_tag(photo, size: 64, css_class: "")
    if photo.image.attached?
      image_tag photo.image.variant(resize_to_fill: [ size, size ], saver: { quality: 80 }),
        class: css_class, loading: "lazy"
    end
  end

  # Renders a user's profile picture as a variant, falling back to a circle
  # with their initial when they haven't uploaded one.
  def avatar_tag(user, size: 64, css_class: "")
    return "" unless user

    base_class = "rounded-full object-cover shrink-0 #{css_class}"
    if user.profile_picture.attached?
      image_tag user.profile_picture.variant(resize_to_fill: [ size, size ], saver: { quality: 80 }),
        class: base_class, loading: "lazy", alt: user.username, title: user.username
    else
      content_tag :div, user.username.first.upcase,
        class: "#{base_class} bg-stone-300 dark:bg-stone-700 text-stone-700 dark:text-stone-200 flex items-center justify-center font-medium",
        title: user.username
    end
  end

  # Formats a trip's entry date span, e.g. "12-18 Jan 2026", collapsing to a
  # single date when a trip's entries all happened on the same day.
  def trip_date_range_text(trip)
    range = trip.entry_date_range
    return nil unless range

    first, last = range.map(&:to_date)
    return first.strftime("%-d %b %Y") if first == last

    if first.year == last.year && first.month == last.month
      "#{first.strftime('%-d')}-#{last.strftime('%-d %b %Y')}"
    elsif first.year == last.year
      "#{first.strftime('%-d %b')} - #{last.strftime('%-d %b %Y')}"
    else
      "#{first.strftime('%-d %b %Y')} - #{last.strftime('%-d %b %Y')}"
    end
  end

  def render_markdown(text)
    return "" if text.blank?
    renderer = Redcarpet::Render::HTML.new(filter_html: true, safe_links_only: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, strikethrough: true)
    sanitize markdown.render(text), tags: %w[p br strong em a ul ol li blockquote code pre h1 h2 h3 h4 img table thead tbody tr th td del],
      attributes: %w[href src alt title]
  end
end
