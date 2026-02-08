require "../src/gemframe_sample/core"

bridge = GemframeSample::Bridge.new(->(_js : String) { })
container = GemframeSample::ServiceContainer.new(bridge)
begin
  GemframeSample::App.register_commands(bridge: bridge, container: container)
  GemframeSample::Framework.register_all_typed_event_signatures(bridge: bridge)
  GemframeSample::Framework::BridgeBindingsGenerator.generate!(bridge)
ensure
  container.shutdown
end
