class ImportsController < ApplicationController
  before_action :require_adventurer

  MAX_UPLOAD_BYTES = 2.gigabytes

  def create
    archive = params[:archive]
    if archive.blank?
      redirect_to edit_settings_path, alert: "Choose a .zip file to import." and return
    end

    if archive.size > MAX_UPLOAD_BYTES
      redirect_to edit_settings_path, alert: "That file is too large to import." and return
    end

    conflict_policy = params[:conflict_policy] == "duplicate" ? :duplicate : :overwrite

    result = Importing::TripArchiveImporter.new(
      archive.path, importing_user: Current.user, conflict_policy: conflict_policy
    ).import!

    redirect_to edit_settings_path, notice: summarize(result)
  rescue Importing::InvalidManifestError => e
    redirect_to edit_settings_path, alert: "Import failed: #{e.message}"
  end

  private
    def summarize(result)
      parts = []
      parts << "imported #{count(result.imported, 'trip')}" if result.imported.positive?
      parts << "overwrote #{count(result.overwritten, 'trip')}" if result.overwritten.positive?
      parts << "#{count(result.skipped_trips.size, 'trip')} failed to import" if result.skipped_trips.any?

      summary = parts.any? ? parts.join(", ").capitalize + "." : "Nothing was imported."
      summary += " #{count(result.warnings.size, 'item')} skipped (unresolved users or invalid files)." if result.warnings.any?
      summary
    end

    def count(number, word)
      "#{number} #{word}#{'s' unless number == 1}"
    end
end
