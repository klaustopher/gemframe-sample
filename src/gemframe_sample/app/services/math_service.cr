module GemframeSample
  # Demonstrates grouped bridge methods under the "math" namespace.
  #
  # JavaScript example:
  #   import CrystalBridge from "../framework/generated/crystal_bridge";
  #   const sum = await CrystalBridge.math.add(4, 2);
  #   const quotient = await CrystalBridge.math.divide(4, 2);
  class MathService
    def add(left : Float64, right : Float64) : Float64
      left + right
    end

    def subtract(left : Float64, right : Float64) : Float64
      left - right
    end

    def multiply(left : Float64, right : Float64) : Float64
      left * right
    end

    def divide(left : Float64, right : Float64) : Float64
      raise ArgumentError.new("Cannot divide by zero") if right == 0.0

      left / right
    end
  end
end
