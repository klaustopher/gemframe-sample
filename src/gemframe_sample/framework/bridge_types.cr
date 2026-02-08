module GemframeSample
  struct BridgeError
    include JSON::Serializable

    getter code : String
    getter message : String

    def initialize(@code : String, @message : String)
    end
  end

  struct BridgeResponse
    include JSON::Serializable

    getter ok : Bool
    getter data : JSON::Any?
    getter error : BridgeError?

    def initialize(@ok : Bool, @data : JSON::Any? = nil, @error : BridgeError? = nil)
    end

    def to_json_any : JSON::Any
      JSON.parse(to_json)
    end
  end
end
