# encoding: UTF-8
# Feature detection is required: definition.manifold? arrived in SketchUp 2026.2.
module MattWu
  module BuildableEnvelope
    module SolidCheck
      def self.closed?(body)
        definition = body.definition
        if definition.respond_to?(:manifold?)
          definition.manifold?
        elsif body.respond_to?(:manifold?)
          body.manifold?
        else
          raise ArgumentError, '当前环境缺少闭合实体检查接口'
        end
      end
    end
  end
end
