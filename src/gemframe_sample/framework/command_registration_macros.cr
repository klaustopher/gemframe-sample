module GemframeSample
  module Framework
    macro __typed_method_js_function_name(prefix, method_name)
      {% if prefix.is_a?(NilLiteral) %}
        {{method_name.id.stringify}}
      {% else %}
        {{prefix}}.empty? ? {{method_name.id.stringify}} : {{prefix}} + "." + {{method_name.id.stringify}}
      {% end %}
    end

    macro register_typed_method_command(bridge, object, methods, prefix = nil)
      {% object_type = nil %}
      {% if object.is_a?(Cast) %}
        {% object_type = object.to %}
      {% elsif object.is_a?(Var) %}
        {% arg = @def.args.find { |a| a.name == object.id } %}
        {% if arg && arg.restriction %}
          {% object_type = arg.restriction %}
        {% end %}
      {% elsif object.is_a?(Call) %}
        {% if object.args.size != 0 %}
          {{ raise "Could not infer type for call '#{object.stringify}' with arguments. Use an explicit cast, for example: #{object.stringify}.as(YourServiceType)" }}
        {% end %}

        {% receiver = object.receiver %}
        {% receiver_type = nil %}

        {% if receiver.is_a?(Var) %}
          {% receiver_arg = @def.args.find { |a| a.name == receiver.id } %}
          {% if receiver_arg && receiver_arg.restriction %}
            {% receiver_type = receiver_arg.restriction %}
          {% end %}
        {% elsif receiver.is_a?(Cast) %}
          {% receiver_type = receiver.to %}
        {% end %}

        {% if receiver_type %}
          {% receiver_methods = receiver_type.resolve.methods.select { |m| m.name == object.name.id } %}
          {% if receiver_methods.empty? %}
            {{ raise "No method named '#{object.name}' found on #{receiver_type.resolve} while inferring object type for '#{object.stringify}'" }}
          {% end %}
          {% if receiver_methods.size > 1 %}
            {{ raise "Method '#{object.name}' on #{receiver_type.resolve} is overloaded. Use an explicit cast for '#{object.stringify}' so the intended service type is unambiguous." }}
          {% end %}

          {% receiver_method = receiver_methods.first %}
          {% object_type = receiver_method.return_type %}
        {% end %}
      {% end %}

      {% if object_type.nil? %}
        {{ raise "Could not infer type for object '#{object.stringify}'. Use an explicit cast, for example: #{object.stringify}.as(YourServiceType)" }}
      {% end %}

      {% if methods.is_a?(TupleLiteral) %}
        {% if methods.size == 0 %}
          {{ raise "register_typed_method_command requires at least one method name" }}
        {% end %}

        {% for method_name in methods %}
          Framework.__register_typed_method_command_single(
            {{bridge}},
            Framework.__typed_method_js_function_name({{prefix}}, {{method_name}}),
            {{object_type}},
            {{object}},
            {{method_name}}
          )
        {% end %}
      {% else %}
        Framework.__register_typed_method_command_single(
          {{bridge}},
          Framework.__typed_method_js_function_name({{prefix}}, {{methods}}),
          {{object_type}},
          {{object}},
          {{methods}}
        )
      {% end %}
    end

    macro __register_typed_method_command_single(bridge, js_function_name, object_type, object, method_name)
      {% method_defs = object_type.resolve.methods.select { |m| m.name == method_name.id } %}
      {% if method_defs.empty? %}
        {{ raise "No method named #{method_name.id} found on #{object_type.resolve}" }}
      {% end %}
      {% if method_defs.size > 1 %}
        {{ raise "Method #{method_name.id} on #{object_type.resolve} is overloaded; typed auto-registration supports non-overloaded methods only" }}
      {% end %}
      {% method = method_defs.first %}
      {% for arg in method.args %}
        {% if arg.restriction.nil? %}
          {{ raise "Method #{object_type.resolve}##{method_name.id} argument '#{arg.name}' must have an explicit type restriction" }}
        {% end %}
      {% end %}
      {% return_type = method.return_type || "JSON".id %}

      {% for arg in method.args %}
        Framework.__register_bridge_type(
          {{bridge}},
          {{arg.restriction}}
        )
      {% end %}
      Framework.__register_bridge_type(
        {{bridge}},
        {{return_type}}
      )

      {{bridge}}.register_command(
        {{js_function_name}},
        {% if method.args.empty? %}
          [] of Bridge::CommandParam,
        {% else %}
          [
            {% for arg in method.args %}
              Bridge::CommandParam.new(
                {{arg.name.stringify}},
                {{arg.restriction.stringify}},
                {{arg.default_value.nil?}}
              ),
            {% end %}
          ],
        {% end %}
        {{return_type.stringify}}
      ) do |args|
        __args = args.as_a? || [] of JSON::Any
        __result = {{object}}.{{method_name.id}}(
          {% last_arg_index = method.args.size - 1 %}
          {% for arg, index in method.args %}
            begin
              {% if arg.default_value %}
                if __args.size > {{index}}
                  Bridge.convert_json_arg(__args[{{index}}], {{arg.restriction}}, {{arg.name.stringify}})
                else
                  {{arg.default_value}}
                end
              {% else %}
                __arg_{{index}} = __args[{{index}}]? || raise ArgumentError.new("Missing required argument: {{arg.name}}")
                Bridge.convert_json_arg(__arg_{{index}}, {{arg.restriction}}, {{arg.name.stringify}})
              {% end %}
            end{% if index < last_arg_index %}, {% end %}
          {% end %}
        )
        Bridge.to_json_any(__result)
      end
    end

    macro __register_bridge_type(bridge, type_ref)
      {% type_name = type_ref.stringify %}
      {% primitives = ::GemframeSample::Framework::TypeMetadata::PRIMITIVE_TYPE_NAMES %}

      {% skip = false %}
      {% skip = true if primitives.includes?(type_name) %}
      {% skip = true if type_name.includes?('|') %}
      {% skip = true if type_name.starts_with?("Array(") %}
      {% skip = true if type_name.starts_with?("Hash(") %}
      {% skip = true if type_name.starts_with?("Tuple(") %}

      {% unless skip %}
        {% resolved = type_ref.resolve %}
        {% inits = resolved.methods.select { |m|
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
          {{bridge}}.register_type(
            {{type_name}},
            [] of Bridge::TypeField
          )
        {% else %}
          {% init = inits.first %}
          {% for candidate in inits %}
            {% if candidate.args.size > init.args.size %}
              {% init = candidate %}
            {% end %}
          {% end %}
          {% for arg in init.args %}
            {% if arg.restriction.nil? %}
              {{ raise "Initializer argument '#{arg.name}' on #{resolved} must have an explicit type restriction" }}
            {% end %}
          {% end %}

          {{bridge}}.register_type(
            {{type_name}},
            [
              {% for arg in init.args %}
                Bridge::TypeField.new(
                  {{arg.name.stringify}},
                  {{arg.restriction.stringify}},
                  {{arg.default_value.nil?}}
                ),
              {% end %}
            ]
          )
        {% end %}
      {% end %}
    end
  end
end
