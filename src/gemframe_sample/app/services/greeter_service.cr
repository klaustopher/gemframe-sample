module GemframeSample
  # Example of typed arguments + validation in application logic.
  #
  # JavaScript example:
  #   import CrystalBridge from "../framework/generated/crystal_bridge";
  #   const text = await CrystalBridge.greeter.greet("Ada", new Date().toISOString());
  #   console.log(text);
  class GreeterService
    def greet(name : String, time_of_day_iso8601 : String) : String
      parsed_time = begin
        Time::Format::ISO_8601_DATE_TIME.parse(time_of_day_iso8601)
      rescue ex : Time::Format::Error
        raise ArgumentError.new("time_of_day_iso8601 must be a valid ISO8601 string")
      end
      salutation = salutation_for_hour(parsed_time.hour)
      "#{salutation}, #{name}."
    end

    private def salutation_for_hour(hour : Int32) : String
      case hour
      when 5..11
        "Good morning"
      when 12..17
        "Good afternoon"
      when 18..21
        "Good evening"
      else
        "Good night"
      end
    end
  end
end
