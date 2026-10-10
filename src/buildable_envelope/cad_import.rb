# encoding: UTF-8
module MattWu
  module BuildableEnvelope
    module CadImport
      extend self
      OPTIONS = {preserve_origin: true,merge_coplanar_faces: false,orient_faces: false,import_materials: true,show_summary: true}.freeze
      def validate_path(path)
        raise ArgumentError, '仅支持 DWG 或 DXF 文件' unless ['.dwg','.dxf'].include?(File.extname(path.to_s).downcase)
        raise ArgumentError, 'CAD 文件不存在' unless File.file?(path)
        path
      end
      def load_definition(model,path)
        validate_path(path)
        definition=model.definitions.import(path,OPTIONS.dup)
        raise ArgumentError, 'CAD 导入未成功，请检查文件版本及 SketchUp CAD 导入支持' unless definition && definition.valid? && !definition.entities.empty?
        definition
      end
      # Leaves existing root geometry untouched. Native importer settings control
      # CAD units; preserve_origin keeps drawing coordinates, without recentering.
      def place(model,definition,name,transformation)
        raise ArgumentError, '请退出组或组件编辑后导入' if model.active_path
        previous=model.selection.to_a
        operation=false
        begin
          model.start_operation('插件导入 CAD',true);operation=true
          instance=model.entities.add_instance(definition,transformation)
          instance.name=name
          model.selection.clear
          model.selection.add(instance)
          model.commit_operation;operation=false
          instance
        rescue
          model.abort_operation if operation
          model.selection.clear
          previous.each { |entity| model.selection.add(entity) if entity.valid? }
          raise
        end
      end
      def tags(entities,out=[],depth=0)
        raise ArgumentError, 'CAD 嵌套超过 20 层' if depth > 20
        entities.each do |entity|
          if entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
            out << entity.layer.name
          elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            out << entity.layer.name
            children=entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
            tags(children,out,depth+1)
          end
        end
        out.uniq.sort
      end
    end
  end
end
