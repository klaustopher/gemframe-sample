module GemframeSample
  module Framework
    module TypeMetadata
      PRIMITIVE_TYPE_NAMES = {
        "String", "Bool", "Nil", "JSON::Any", "JSON", "Time",
        "Int8", "Int16", "Int32", "Int64", "Int128",
        "UInt8", "UInt16", "UInt32", "UInt64", "UInt128",
        "Float32", "Float64",
      }

      PRIMITIVE_TS_TYPE_MAP = {
        "String" => "string",
        "Bool"   => "boolean",
        "Nil"    => "null",
        "JSON::Any" => "unknown",
        "JSON"   => "unknown",
        "Time"   => "string",
        "Int8"   => "number",
        "Int16"  => "number",
        "Int32"  => "number",
        "Int64"  => "number",
        "Int128" => "number",
        "UInt8"  => "number",
        "UInt16" => "number",
        "UInt32" => "number",
        "UInt64" => "number",
        "UInt128" => "number",
        "Float32" => "number",
        "Float64" => "number",
      }

      extend self

      def primitive_type?(type : String) : Bool
        PRIMITIVE_TS_TYPE_MAP.has_key?(type)
      end

      def ts_primitive_type(type : String) : String?
        PRIMITIVE_TS_TYPE_MAP[type]?
      end
    end
  end
end
