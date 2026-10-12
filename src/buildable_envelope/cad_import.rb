# encoding: UTF-8
module MattWu
  module BuildableEnvelope
    module CadImport
      extend self
      OPTIONS = {preserve_origin: true,merge_coplanar_faces: false,orient_faces: false,import_materials: true,show_summary: false}.freeze
      def validate_path(path)
        raise ArgumentError, '仅支持 DWG 或 DXF 文件' unless ['.dwg','.dxf'].include?(File.extname(path.to_s).downcase)
        raise ArgumentError, 'CAD 文件不存在' unless File.file?(path)
        path
      end
      def load_definition(model,path)
        validate_path(path)
        definition=model.definitions.import(path,OPTIONS.dup)
        raise ArgumentError, 'CAD 导入未成功，请检查文件版本及 SketchUp CAD 导入支持' unless definition && definition.valid? && definition.entities.length > 0
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
      def focus(model,instance)
        raise ArgumentError, '导入的 CAD 组件已失效' unless instance && instance.valid?
        model.selection.clear
        model.selection.add(instance)
        model.active_view.zoom(instance)
        true
      end

      def summary(instance)
        counts={edges: 0,faces: 0,components: 0,groups: 0,other: 0}
        layer_names=[];visited=0;truncated=false
        walk=lambda do |entities,depth|
          if depth > 20
            truncated=true
            next
          end
          entities.each do |entity|
            visited+=1
            if visited > 250000
              truncated=true
              break
            end
            layer_names << entity.layer.name if entity.respond_to?(:layer)
            case entity
            when Sketchup::Edge then counts[:edges]+=1
            when Sketchup::Face then counts[:faces]+=1
            when Sketchup::Group
              counts[:groups]+=1
              walk.call(entity.entities,depth+1)
            when Sketchup::ComponentInstance
              counts[:components]+=1
              walk.call(entity.definition.entities,depth+1)
            else counts[:other]+=1
            end
          end
        end
        walk.call(instance.definition.entities,0)
        bounds=instance.bounds
        {tags: layer_names.uniq.sort,counts: counts,truncated: truncated,
          width: bounds.width.to_f*0.0254,height: bounds.height.to_f*0.0254,depth: bounds.depth.to_f*0.0254}
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
