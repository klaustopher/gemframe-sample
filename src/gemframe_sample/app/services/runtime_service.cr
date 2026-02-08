module GemframeSample
  Framework.serializable_record RuntimeInfo, crystal_version : String, frontend_url : String

  # Returns basic runtime metadata for startup diagnostics.
  #
  # JavaScript example:
  #   import CrystalBridge from "../framework/generated/crystal_bridge";
  #   const info = await CrystalBridge.runtime.info();
  #   console.log(info.crystal_version, info.frontend_url);
  class RuntimeService
    def info : RuntimeInfo
      RuntimeInfo.new(Crystal::VERSION, FRONTEND_URL)
    end
  end
end
