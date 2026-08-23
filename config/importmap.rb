# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "leaflet" # @1.9.4
pin "@rails/activestorage", to: "activestorage.js" # @7.2.302
pin "emoji-picker-element" # @1.29.1
pin "emoji-picker-element/picker", to: "emoji-picker-element--picker.js" # @1.29.1
pin "emoji-picker-element/database", to: "emoji-picker-element--database.js" # @1.29.1
