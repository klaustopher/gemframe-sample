module GemframeSample
  # Minimal command used to validate command invocation end-to-end.
  #
  # JavaScript example:
  #   import CrystalBridge from "../framework/generated/crystal_bridge";
  #   const message = await CrystalBridge.hello("John");
  #   console.log(message);
  class HelloService
    def hello(name : String) : String
      "Hello #{name} from Crystal"
    end
  end
end
