require "uri"

module GemframeSample
  # App-level configuration consumed by the application entrypoint.
  # Parsing env vars here keeps configuration concerns out of service logic.
  FRONTEND_URL = ENV["GEMFRAME_SAMPLE_FRONTEND_URL"]? || "http://127.0.0.1:5173"
  WINDOW_ID    = "main"

  FRONTEND_DIR = File.expand_path("../../../frontend", __DIR__)

  MANAGE_VITE = ENV["GEMFRAME_SAMPLE_MANAGE_VITE"]? != "0"

  VITE_URI = URI.parse(FRONTEND_URL)
  VITE_HOST = ENV["GEMFRAME_SAMPLE_VITE_HOST"]? || VITE_URI.host || "127.0.0.1"
  VITE_PORT = begin
    raw = ENV["GEMFRAME_SAMPLE_VITE_PORT"]? || VITE_URI.port.try(&.to_s) || "5173"
    parsed = raw.to_i?
    parsed && parsed > 0 ? parsed : 5173
  end
end
