module GemframeSample
  module TerminalLog
    extend self

    MUTEX = Mutex.new

    def bridge(direction : String, name : String, payload : JSON::Any? = nil) : Nil
      timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      payload_json = payload ? payload.to_json : "null"
      line = "[#{timestamp}] [bridge] #{direction} #{name} payload=#{payload_json}"

      MUTEX.synchronize do
        STDOUT.puts(line)
      end
    end

    def error(context : String, ex : Exception) : Nil
      timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      line = "[#{timestamp}] [error] #{context}: #{ex.message || ex.class.name}"

      MUTEX.synchronize do
        STDERR.puts(line)
      end
    end
  end
end
