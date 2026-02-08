module GemframeSample
  module Framework
    def self.__typed_event_signatures_storage : Array(Bridge::EventSignature)
      @@__typed_event_signatures ||= [] of Bridge::EventSignature
    end

    def self.typed_event_signatures : Array(Bridge::EventSignature)
      __typed_event_signatures_storage.dup
    end

    macro __typed_event_signature_literal(method_name, topic, payload_type)
      {% inits = payload_type.resolve.methods.select { |m|
           m.name == "initialize".id &&
             (
               m.args.size != 1 ||
               m.args.first.restriction.nil? ||
               (
                 m.args.first.restriction.stringify != "JSON::PullParser" &&
                 m.args.first.restriction.stringify != "::JSON::PullParser"
               )
             )
         } %}
      {% if inits.empty? %}
        {{ raise "No initialize method found on #{payload_type.resolve}; cannot derive event payload fields" }}
      {% end %}
      {% init = inits.first %}
      {% for candidate in inits %}
        {% if candidate.args.size > init.args.size %}
          {% init = candidate %}
        {% end %}
      {% end %}
      {% for arg in init.args %}
        {% if arg.restriction.nil? %}
          {{ raise "Initializer argument '#{arg.name}' on #{payload_type.resolve} must have an explicit type restriction" }}
        {% end %}
      {% end %}

      Bridge::EventSignature.new(
        {{method_name.id.stringify}},
        {{topic}},
        {{payload_type.stringify}},
        [
          {% for arg in init.args %}
            Bridge::EventField.new(
              {{arg.name.stringify}},
              {{arg.restriction.stringify}},
              {{arg.default_value.nil?}}
            ),
          {% end %}
        ]
      )
    end

    macro define_typed_event(method_name, topic, payload_type)
      class ::GemframeSample::Bridge
        def {{method_name.id}}(payload : {{payload_type}}) : JSON::Any
          emit_typed_event({{topic}}, payload)
        end
      end

      Framework.__append_typed_event_signature(
        {{method_name}},
        {{topic}},
        {{payload_type}}
      )
    end

    macro __append_typed_event_signature(method_name, topic, payload_type)
      module ::GemframeSample::Framework
        __typed_event_signatures = __typed_event_signatures_storage
        __typed_event_signatures << ::GemframeSample::Framework.__typed_event_signature_literal(
          {{method_name}},
          {{topic}},
          {{payload_type}}
        )
      end
    end

    def self.register_all_typed_event_signatures(*, bridge : Bridge) : Nil
      typed_event_signatures.each do |signature|
        type_fields = signature.fields.map do |field|
          Bridge::TypeField.new(field.name, field.type, field.required)
        end

        bridge.register_type(signature.payload_type, type_fields)
        bridge.register_event(
          signature.method,
          signature.topic,
          signature.payload_type,
          signature.fields
        )
      end
    end
  end
end
