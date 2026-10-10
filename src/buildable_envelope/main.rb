# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require_relative 'geometry'
module MattWu
  module BuildableEnvelope
    extend self
    INCH_TO_M = 0.0254
    DICTIONARY = 'MattWuBuildableEnvelope'

    def world_point(point, transformation)
      p = point.transform(transformation)
      [p.x.to_f*INCH_TO_M,p.y.to_f*INCH_TO_M,p.z.to_f*INCH_TO_M]
    end

    def parcel(points, name)
      z = points.first[2]
      raise ArgumentError, '仅支持水平红线，标高误差不得超过 1 毫米' if points.any? { |p| (p[2]-z).abs > 0.001 }
      origin = points.first
      poly = points.map { |p| [p[0]-origin[0],p[1]-origin[1]] }
      Geometry.validate(poly)
      { name: name, points: poly, origin: origin, height: 36.0, floor_height: 3.6,
        setbacks: Array.new(poly.length,5.0) }
    end

    def edge_cycles(edges, transformation, name)
      adjacency = Hash.new { |h,k| h[k] = [] }
      edges.each { |e| e.vertices.each { |v| adjacency[v] << e } }
      raise ArgumentError, '红线未闭合或存在分叉，请选完整闭合线' unless adjacency.values.all? { |list| list.length == 2 }
      unseen = edges.dup
      parcels = []
      until unseen.empty?
        edge = unseen.first
        start = edge.start
        current = start
        points = []
        loop do
          points << world_point(current.position, transformation)
          unseen.delete(edge)
          current = edge.other_vertex(current)
          break if current == start
          edge = adjacency[current].find { |candidate| unseen.include?(candidate) }
          raise ArgumentError, '红线连接异常' unless edge
        end
        parcels << parcel(points, name + ' / ' + (parcels.length+1).to_s)
      end
      # Contained cycles can be holes; do not silently fill them.
      parcels.combination(2) do |a,b|
        ap = a[:points].map { |p| [p[0]+a[:origin][0],p[1]+a[:origin][1]] }
        bp = b[:points].map { |p| [p[0]+b[:origin][0],p[1]+b[:origin][1]] }
        raise ArgumentError, '闭合线存在嵌套或交叠，请先整理为无内孔地块面' if polygons_overlap?(ap,bp)
      end
      parcels
    end

    def inside?(p,poly)
      hit = false
      poly.each_index do |i|
        a,b = poly[i],poly[(i+1)%poly.length]
        return true if Geometry.on_segment?(p,a,b)
        if (a[1]>p[1]) != (b[1]>p[1])
          x = a[0]+(p[1]-a[1])*(b[0]-a[0])/(b[1]-a[1])
          hit = !hit if p[0] < x
        end
      end
      hit
    end

    def polygons_overlap?(a,b)
      return true if inside?(a.first,b) || inside?(b.first,a)
      a.each_index.any? do |i|
        b.each_index.any? { |j| Geometry.intersects?(a[i],a[(i+1)%a.length],b[j],b[(j+1)%b.length]) }
      end
    end

    def scan(entities, transformation, name, results, errors, depth = 0)
      raise ArgumentError, '组嵌套超过 20 层' if depth > 20
      faces = entities.grep(Sketchup::Face)
      faces.each_with_index do |face,i|
        begin
          raise ArgumentError, '暂不支持带内孔的地块面' if face.loops.length != 1
          points = face.outer_loop.vertices.map { |v| world_point(v.position, transformation) }
          results << parcel(points, name + ' / 面' + (i+1).to_s)
        rescue ArgumentError => error
          errors << name + ': ' + error.message
        end
      end
      edges = entities.grep(Sketchup::Edge).select { |e| e.faces.empty? }
      unless edges.empty?
        begin
          results.concat(edge_cycles(edges,transformation,name + ' / 线'))
        rescue ArgumentError => error
          errors << name + ': ' + error.message
        end
      end
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        next if entity.get_attribute(DICTIONARY,'generated')
        child = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        child_name = entity.name.empty? ? name + ' / 组' : name + ' / ' + entity.name
        scan(child,transformation*entity.transformation,child_name,results,errors,depth+1)
      end
    end

    def capture(model)
      raise ArgumentError, '请退出组或组件编辑后再操作' if model.active_path
      raise ArgumentError, '请选择用地面、闭合红线或包含红线的组' if model.selection.empty?
      results,errors = [],[]
      scan(model.selection.to_a,Geom::Transformation.new,'地块',results,errors)
      raise ArgumentError, '没有有效地块。' + errors.join('；') if results.empty?
      raise ArgumentError, '单批最多 50 个地块，请分批处理' if results.length > 50
      results.each_with_index { |p,i| p[:id] = i.to_s; p[:name] = '地块' + (i+1).to_s + ' · ' + p[:name] }
      [results,errors]
    end

    def signature(parcels)
      parcels.map { |p| [p[:origin],p[:points]] }
    end

    def show_dialog
      if Sketchup.version.to_i < 23
        UI.messagebox('需要 SketchUp 2023 或以上桌面版')
        return
      end
      @model = Sketchup.active_model
      @parcels,@errors = capture(@model)
      @signature = signature(@parcels)
      @dialog.close if @dialog
      @dialog = UI::HtmlDialog.new(dialog_title: '可建体量 · 退线 + 限高',
        preferences_key: DICTIONARY, scrollable: true, resizable: true, width: 980, height: 760)
      @dialog.set_file(File.join(__dir__,'ui.html'))
      @dialog.add_action_callback('ready') { |_context| send_data }
      @dialog.add_action_callback('reload') do |_context|
        begin
          @model = Sketchup.active_model
          @parcels,@errors = capture(@model)
          @signature = signature(@parcels)
          send_data
        rescue => error
          report(error.message)
        end
      end
      @dialog.add_action_callback('generate') do |_context,payload|
        begin
          raise ArgumentError, '模型已经切换，请重新读取选择' unless Sketchup.active_model == @model
          current,_errors = capture(@model)
          raise ArgumentError, '选择或红线已改变，请重新读取选择' unless signature(current) == @signature
          generate(JSON.parse(payload))
        rescue => error
          report(error.message)
        end
      end
      @dialog.show
    rescue => error
      UI.messagebox(error.message)
    end

    def send_data
      @dialog.execute_script('receive(' + JSON.generate(parcels: @parcels, errors: @errors) + ')')
    end

    def report(message)
      @dialog.execute_script('report(' + JSON.generate(message) + ')') if @dialog
    end

    def numeric(value, positive = false)
      number = Float(value)
      raise ArgumentError, '数值须有限且非负；高度与层高须大于零' unless number.finite? && (positive ? number > 0 : number >= 0)
      number
    end

    def merged_faces(group,cells,origin)
      entities = group.entities
      cells.each do |cell|
        points = cell.map { |p| Geom::Point3d.new((p[0]+origin[0])/INCH_TO_M,(p[1]+origin[1])/INCH_TO_M,origin[2]/INCH_TO_M) }
        face = entities.add_face(points)
        raise ArgumentError, 'SketchUp 无法创建局部面，请检查过短边' unless face
        face.reverse! if face.normal.z < 0
      end
      internal = entities.grep(Sketchup::Edge).select { |e| e.faces.length == 2 }
      entities.erase_entities(internal) unless internal.empty?
      faces = entities.grep(Sketchup::Face)
      actual = faces.sum { |f| f.area*INCH_TO_M*INCH_TO_M }
      expected = Geometry.area(cells)
      raise ArgumentError, '面合并面积不一致，已取消此地块' if (actual-expected).abs > [0.001,expected*1.0e-6].max
      faces.each { |f| f.reverse! if f.normal.z < 0 }
      faces
    end

    def generate(inputs)
      raise ArgumentError, '参数列表无效，请重新读取' unless inputs.is_a?(Array) && inputs.length == @parcels.length
      messages = @errors.map { |message| '输入跳过：' + message }
      prepared = @parcels.each_with_index.map do |source,i|
        begin
          input = inputs[i]
          raise ArgumentError, '参数地块编号不匹配' unless input['id'] == source[:id]
          height = numeric(input['height'],true)
          floor_height = numeric(input['floor_height'],true)
          setbacks = input.fetch('setbacks').map { |v| numeric(v) }
          cells = Geometry.inset(source[:points],setbacks)
          name = input['name'].to_s.strip[0,100]
          name = source[:name] if name.empty?
          { source: source, height: height, floor_height: floor_height,
            cells: cells, setbacks: setbacks, name: name }
        rescue => error
          messages << source[:name] + '：失败 · ' + error.message
          nil
        end
      end.compact
      operation = false
      @model.start_operation('批量生成可建体量',true)
      operation = true
      success = 0
      prepared.each do |data|
        group = nil
        begin
          area = Geometry.area(data[:cells])
          if area <= Geometry::AREA_EPS
            messages << data[:name] + '：无可建范围'
            next
          end
          group = @model.entities.add_group
          group.name = data[:name] + ' · 可建包络'
          group.set_attribute(DICTIONARY,'generated',true)
          footprint = group.entities.add_group
          footprint.name = '可建范围（隐藏，展开组可显示）'
          merged_faces(footprint,data[:cells],data[:source][:origin])
          footprint.hidden = true
          volume = group.entities.add_group
          volume.name = '限高体量'
          faces = merged_faces(volume,data[:cells],data[:source][:origin])
          faces.each { |face| face.pushpull(data[:height]/INCH_TO_M) }
          raise ArgumentError, '生成结果不是闭合实体，已取消此地块' unless volume.manifold?
          volume.material = Sketchup::Color.new(92,160,176)
          floors = (data[:height]/data[:floor_height] + 1.0e-9).floor
          gfa = area*floors
          label = format("%s\n可建占地：%.2f ㎡\n限高：%.2f m · %d 层\n满铺估算建筑面积：%.2f ㎡\n层高：%.2f m · 圆角保守退线",
            data[:name],area,data[:height],floors,gfa,data[:floor_height])
          origin = data[:source][:origin]
          anchor = Geom::Point3d.new(origin[0]/INCH_TO_M,origin[1]/INCH_TO_M,(origin[2]+data[:height])/INCH_TO_M)
          group.entities.add_text(label,anchor)
          group.set_attribute(DICTIONARY,'parameters',JSON.generate(data.reject { |key,_| [:cells,:source].include?(key) }))
          group.set_attribute(DICTIONARY,'footprint_m2',area)
          group.set_attribute(DICTIONARY,'estimated_gfa_m2',gfa)
          messages << format('%s：成功 · 占地 %.2f ㎡ · 估算建筑面积 %.2f ㎡',data[:name],area,gfa)
          success += 1
        rescue => error
          group.erase! if group && group.valid?
          messages << data[:name] + '：失败 · ' + error.message
        end
      end
      @model.commit_operation
      operation = false
      report("完成：成功 " + success.to_s + " 个地块\n" + messages.join("\n"))
    rescue => error
      @model.abort_operation if operation
      raise error
    end

    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('可建体量快速生成…') { show_dialog }
      file_loaded(__FILE__)
    end
  end
end
