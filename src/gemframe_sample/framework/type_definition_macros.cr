module GemframeSample
  module Framework
    macro serializable_record(name, *fields)
      record {{name}}, {{fields.splat}}
      struct {{name.id}}
        include JSON::Serializable
      end
    end
  end
end
