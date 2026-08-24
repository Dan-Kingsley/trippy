class ImportsController < ApplicationController
  before_action :require_adventurer

  MAX_UPLOAD_BYTES = 2.gigabytes

  def create
    archive = params[:archive]
    if archive.blank?
      redirect_to edit_settings_path, alert: t("imports.choose_file") and return
    end

    if archive.size > MAX_UPLOAD_BYTES
      redirect_to edit_settings_path, alert: t("imports.too_large") and return
    end

    conflict_policy = params[:conflict_policy] == "duplicate" ? :duplicate : :overwrite

    result = Importing::TripArchiveImporter.new(
      archive.path, importing_user: Current.user, conflict_policy: conflict_policy
    ).import!

    redirect_to edit_settings_path, notice: summarize(result)
  rescue Importing::InvalidManifestError => e
    redirect_to edit_settings_path, alert: t("imports.failed", error: e.message)
  end

  private
    def summarize(result)
      parts = []
      parts << t("imports.imported", count: t("counts.trip", count: result.imported)) if result.imported.positive?
      parts << t("imports.overwrote", count: t("counts.trip", count: result.overwritten)) if result.overwritten.positive?
      parts << t("imports.failed_count", count: t("counts.trip", count: result.skipped_trips.size)) if result.skipped_trips.any?

      summary = parts.any? ? parts.join(", ").capitalize + "." : t("imports.nothing_imported")
      summary += " #{t("imports.warnings", count: t("counts.item", count: result.warnings.size))}" if result.warnings.any?
      summary
    end
end
