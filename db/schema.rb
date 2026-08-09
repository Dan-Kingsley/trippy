# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_09_060540) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.integer "trip_entry_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["parent_id"], name: "index_comments_on_parent_id"
    t.index ["trip_entry_id"], name: "index_comments_on_trip_entry_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "photos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "latitude"
    t.float "longitude"
    t.integer "position", default: 0, null: false
    t.datetime "taken_at"
    t.integer "trip_entry_id", null: false
    t.datetime "updated_at", null: false
    t.integer "uploaded_by_id"
    t.index ["trip_entry_id", "position"], name: "index_photos_on_trip_entry_id_and_position"
    t.index ["trip_entry_id"], name: "index_photos_on_trip_entry_id"
    t.index ["uploaded_by_id"], name: "index_photos_on_uploaded_by_id"
  end

  create_table "reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.integer "trip_entry_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["trip_entry_id", "user_id", "emoji"], name: "index_reactions_on_entry_user_emoji", unique: true
    t.index ["trip_entry_id"], name: "index_reactions_on_trip_entry_id"
    t.index ["user_id"], name: "index_reactions_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "trip_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["trip_id", "user_id"], name: "index_trip_accesses_on_trip_id_and_user_id", unique: true
    t.index ["trip_id"], name: "index_trip_accesses_on_trip_id"
    t.index ["user_id"], name: "index_trip_accesses_on_user_id"
  end

  create_table "trip_collaborators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["trip_id", "user_id"], name: "index_trip_collaborators_on_trip_id_and_user_id", unique: true
    t.index ["trip_id"], name: "index_trip_collaborators_on_trip_id"
    t.index ["user_id"], name: "index_trip_collaborators_on_user_id"
  end

  create_table "trip_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.float "latitude"
    t.float "longitude"
    t.boolean "manual_location", default: false, null: false
    t.boolean "manual_time", default: false, null: false
    t.datetime "occurred_at"
    t.string "title", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.integer "views_count", default: 0, null: false
    t.index ["created_by_id"], name: "index_trip_entries_on_created_by_id"
    t.index ["trip_id", "occurred_at"], name: "index_trip_entries_on_trip_id_and_occurred_at"
    t.index ["trip_id"], name: "index_trip_entries_on_trip_id"
  end

  create_table "trip_entry_collaborators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "trip_entry_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["trip_entry_id", "user_id"], name: "index_trip_entry_collaborators_on_trip_entry_id_and_user_id", unique: true
    t.index ["trip_entry_id"], name: "index_trip_entry_collaborators_on_trip_entry_id"
    t.index ["user_id"], name: "index_trip_entry_collaborators_on_user_id"
  end

  create_table "trip_entry_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "trip_entry_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "visitor_token"
    t.index ["trip_entry_id", "user_id"], name: "index_trip_entry_views_on_trip_entry_id_and_user_id", unique: true
    t.index ["trip_entry_id", "visitor_token"], name: "index_trip_entry_views_on_trip_entry_id_and_visitor_token", unique: true
    t.index ["trip_entry_id"], name: "index_trip_entry_views_on_trip_entry_id"
    t.index ["user_id"], name: "index_trip_entry_views_on_user_id"
  end

  create_table "trips", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "owner_id", null: false
    t.boolean "public", default: false, null: false
    t.string "secret_code", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_trips_on_owner_id"
    t.index ["secret_code"], name: "index_trips_on_secret_code", unique: true
    t.index ["slug"], name: "index_trips_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.boolean "adventurer", default: false, null: false
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "comments", "comments", column: "parent_id"
  add_foreign_key "comments", "trip_entries"
  add_foreign_key "comments", "users"
  add_foreign_key "photos", "trip_entries"
  add_foreign_key "photos", "users", column: "uploaded_by_id"
  add_foreign_key "reactions", "trip_entries"
  add_foreign_key "reactions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "trip_accesses", "trips"
  add_foreign_key "trip_accesses", "users"
  add_foreign_key "trip_collaborators", "trips"
  add_foreign_key "trip_collaborators", "users"
  add_foreign_key "trip_entries", "trips"
  add_foreign_key "trip_entries", "users", column: "created_by_id"
  add_foreign_key "trip_entry_collaborators", "trip_entries"
  add_foreign_key "trip_entry_collaborators", "users"
  add_foreign_key "trip_entry_views", "trip_entries"
  add_foreign_key "trip_entry_views", "users"
  add_foreign_key "trips", "users", column: "owner_id"
end
