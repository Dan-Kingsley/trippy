Rails.application.routes.draw do
  root "home#index"

  resource :session, only: %i[ new create destroy ]
  resource :registration, only: %i[ new create ]
  resource :settings, only: %i[ edit update ]
  resource :import, only: %i[ create ], controller: "imports"

  resources :private_accesses, only: %i[ create ], path: "access"

  # Exports every trip the current user owns, as opposed to trip-scoped
  # `export` below which exports a single trip.
  resource :export, only: %i[ show ], controller: "exports", as: :trips_export

  namespace :admin do
    resources :users, only: %i[ index update ] do
      collection do
        post :grant_adventurer
      end
    end
  end

  resources :trips, param: :slug do
    resource :export, only: %i[ show ], controller: "exports"
    resource :favorite, only: %i[ create destroy ]
    resources :collaborators, only: %i[ create destroy ], controller: "trip_collaborators"

    resources :trip_entries, path: "entries", except: %i[ index ] do
      resources :photos, only: %i[ create destroy update ]
      resources :comments, only: %i[ create destroy ]
      resources :reactions, only: %i[ create destroy ]
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
