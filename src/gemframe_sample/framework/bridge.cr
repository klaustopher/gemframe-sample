module GemframeSample
  class Bridge
    alias CommandHandler = JSON::Any -> JSON::Any

    @emit_js : Proc(String, Nil)
    @commands : Hash(String, RegisteredCommand)
    @events : Hash(String, EventSignature)
    @types : Hash(String, TypeSignature)

    struct CommandParam
      include JSON::Serializable

      getter name : String
      getter type : String
      getter required : Bool

      def initialize(@name : String, @type : String, @required : Bool = true)
      end
    end

    struct CommandSignature
      include JSON::Serializable

      getter command : String
      getter params : Array(CommandParam)
      getter returns : String

      def initialize(@command : String, @params : Array(CommandParam), @returns : String)
      end
    end

    struct EventField
      include JSON::Serializable

      getter name : String
      getter type : String
      getter required : Bool

      def initialize(@name : String, @type : String, @required : Bool = true)
      end
    end

    struct EventSignature
      include JSON::Serializable

      getter method : String
      getter topic : String
      getter payload_type : String
      getter fields : Array(EventField)

      def initialize(
        @method : String,
        @topic : String,
        @payload_type : String,
        @fields : Array(EventField) = [] of EventField
      )
      end
    end

    struct TypeField
      include JSON::Serializable

      getter name : String
      getter type : String
      getter required : Bool

      def initialize(@name : String, @type : String, @required : Bool = true)
      end
    end

    struct TypeSignature
      include JSON::Serializable

      getter name : String
      getter fields : Array(TypeField)

      def initialize(@name : String, @fields : Array(TypeField) = [] of TypeField)
      end
    end

    private class RegisteredCommand
      getter signature : CommandSignature
      getter handler : CommandHandler

      def initialize(@signature : CommandSignature, @handler : CommandHandler)
      end
    end

    def initialize(@emit_js : Proc(String, Nil))
      @commands = {} of String => RegisteredCommand
      @events = {} of String => EventSignature
      @types = {} of String => TypeSignature
    end

    def register_command(
      name : String,
      params : Array(CommandParam) = [] of CommandParam,
      returns : String = "JSON",
      &handler : JSON::Any -> JSON::Any
    ) : Nil
      signature = CommandSignature.new(name, params, returns)
      @commands[name] = RegisteredCommand.new(signature, handler)
    end

    def command_signatures : Array(CommandSignature)
      @commands
        .values
        .map(&.signature)
        .sort_by(&.command)
    end

    def register_event(
      method : String,
      topic : String,
      payload_type : String,
      fields : Array(EventField) = [] of EventField
    ) : Nil
      @events[method] = EventSignature.new(method, topic, payload_type, fields)
    end

    def event_signatures : Array(EventSignature)
      @events
        .values
        .sort_by(&.topic)
    end

    def register_type(name : String, fields : Array(TypeField) = [] of TypeField) : Nil
      existing = @types[name]?
      if existing
        return if existing.fields == fields
        return if existing.fields.empty?
      end

      @types[name] = TypeSignature.new(name, fields)
    end

    def type_signatures : Array(TypeSignature)
      @types
        .values
        .sort_by(&.name)
    end

    def invoke(args : Array(JSON::Any)) : JSON::Any
      command = args[0]?.try(&.as_s?) || return failure("BAD_REQUEST", "Missing command")
      command_args = if args.size > 1
                       args[1..]
                     else
                       [] of JSON::Any
                     end
      TerminalLog.bridge("frontend->backend", command, JSON::Any.new(command_args))
      registered = @commands[command]?
      return failure("UNKNOWN_COMMAND", "Unknown command: #{command}") unless registered

      validate_arity!(registered.signature, command_args.size)
      data = registered.handler.call(JSON::Any.new(command_args))
      BridgeResponse.new(true, data).to_json_any
    rescue ex : ArgumentError
      failure("BAD_REQUEST", ex.message || ex.class.name)
    rescue ex
      TerminalLog.error("frontend->backend invoke", ex)
      failure("INTERNAL_ERROR", ex.message || ex.class.name)
    end

    private def failure(code : String, message : String) : JSON::Any
      BridgeResponse.new(false, nil, BridgeError.new(code, message)).to_json_any
    end

    private def validate_arity!(signature : CommandSignature, provided_count : Int32) : Nil
      required_count = signature.params.count(&.required)
      max_count = signature.params.size

      if provided_count < required_count || provided_count > max_count
        raise ArgumentError.new(
          "Invalid argument count for #{signature.command}: expected #{required_count}..#{max_count}, got #{provided_count}"
        )
      end
    end

    def self.convert_json_arg(raw : JSON::Any, type : T.class, name : String) : T forall T
      Webview::TypedBinding.convert_from_json(raw, type)
    rescue ex
      raise ArgumentError.new("Argument '#{name}' must be #{type}")
    end

    def self.to_json_any(value) : JSON::Any
      case value
      when JSON::Any
        value
      when Int32, Int64, Float64, String, Bool, Nil
        JSON::Any.new(value)
      else
        JSON.parse(value.to_json)
      end
    end

    def emit_event(topic : String, payload : JSON::Any) : JSON::Any
      envelope = event_envelope(topic, payload)
      TerminalLog.bridge("backend->frontend", topic, envelope)
      @emit_js.call(
        "window.__GEMFRAME_SAMPLE__ && " \
        "window.__GEMFRAME_SAMPLE__.__bridgeDispatch(#{envelope.to_json});"
      )
      envelope
    end

    def emit_typed_event(topic : String, payload) : JSON::Any
      emit_event(topic, Bridge.to_json_any(payload))
    end

    private def event_envelope(topic : String, payload : JSON::Any) : JSON::Any
      now = Time.utc
      JSON::Any.new({
        "id"        => JSON::Any.new("#{now.to_unix_ms}-#{Random.rand(1_000_000)}"),
        "version"   => JSON::Any.new(1_i64),
        "window_id" => JSON::Any.new(WINDOW_ID),
        "topic"     => JSON::Any.new(topic),
        "timestamp" => JSON::Any.new(now.to_s("%Y-%m-%dT%H:%M:%S%:z")),
        "payload"   => payload,
      })
    end
  end
end
