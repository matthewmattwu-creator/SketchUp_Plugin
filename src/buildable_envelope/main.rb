# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require_relative 'geometry'
require_relative 'solid_check'
require_relative 'boundary'
require_relative 'cad_import'
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
      boundary_parcel(Boundary.build(points).merge(holes: []),name)
    end

    def boundary_parcel(boundary, name)
      boundary.merge(name: name, height: 36.0, floor_height: 3.6,
        setbacks: Array.new(boundary[:points].length,5.0),
        area: boundary[:area] || Geometry.signed_area(boundary[:points]).abs,
        high_segment: boundary[:points].length > Geometry::SIMPLIFY_THRESHOLD)
    end

    def edge_cycles(edges, transformation, name, errors = [])
      vertices = {}
      links = edges.map do |edge|
        edge.vertices.each { |v| vertices[v] = world_point(v.position,transformation) }
        [edge.start,edge.end]
      end
      loops, diagnostics = Boundary.cycles(vertices,links)
      errors.concat(diagnostics.map { |message| name + ': ' + message })
      valid = loops.select do |points|
        begin
          Boundary.build(points)
          true
        rescue ArgumentError => error
          errors << name + ': ' + error.message
          false
        end
      end
      Boundary.regions(valid).each_with_index.map { |region,i| boundary_parcel(region,name + ' / ' + (i+1).to_s) }
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

    def scan(entities, transformation, name, results, errors, depth = 0, tag = nil, inherited = false)
      raise ArgumentError, '组嵌套超过 20 层' if depth > 20
      faces = entities.grep(Sketchup::Face).select { |entity| tag.nil? || entity.layer.name == tag || (inherited && entity.layer == entity.model.layers[0]) }
      faces.each_with_index do |face,i|
        begin
          loops = [face.outer_loop] + (face.loops - [face.outer_loop])
          regions = Boundary.regions(loops.map { |ring| ring.vertices.map { |v| world_point(v.position,transformation) } })
          raise ArgumentError, '地块面内孔关系异常' unless regions.length == 1 && regions.first[:holes].length == face.loops.length-1
          results << boundary_parcel(regions.first,name + ' / 面' + (i+1).to_s)
        rescue ArgumentError => error
          errors << name + ': ' + error.message
        end
      end
      edges = entities.grep(Sketchup::Edge).select { |e| (tag.nil? || e.layer.name == tag || (inherited && e.layer == e.model.layers[0])) && (e.faces & faces).empty? }
      unless edges.empty?
        begin
          results.concat(edge_cycles(edges,transformation,name + ' / 线',errors))
        rescue ArgumentError => error
          errors << name + ': ' + error.message
        end
      end
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        next if entity.get_attribute(DICTIONARY,'generated')
        child = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        child_name = entity.name.empty? ? name + ' / 组' : name + ' / ' + entity.name
        child_matches = !tag.nil? && (entity.layer == entity.model.layers[0] ? inherited : entity.layer.name == tag)
        scan(child,transformation*entity.transformation,child_name,results,errors,depth+1,tag,child_matches)
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
      parcels.map { |p| [p[:origin],p[:points],p[:holes],p[:source_rings] || p[:source_points]] }
    end

    def show_dialog
      if Sketchup.version.to_i < 23
        UI.messagebox('需要 SketchUp 2023 或以上桌面版')
        return
      end
      @model = Sketchup.active_model
      @cad_mode=false
      @parcels,@errors=[],[]
      begin
        @parcels,@errors=capture(@model) unless @model.selection.empty?
      rescue ArgumentError => error
        @errors=[error.message]
      end
      @signature = signature(@parcels)
      @dialog.close if @dialog
      @dialog = UI::HtmlDialog.new(dialog_title: '可建体量 · 退线 + 限高',
        preferences_key: DICTIONARY, scrollable: true, resizable: true, width: 980, height: 760)
      @dialog.set_file(File.join(__dir__,'ui.html'))
      @dialog.add_action_callback('ready') { |_context| send_data }
      @dialog.add_action_callback('reload') do |_context|
        begin
          @model = Sketchup.active_model
          @cad_mode=false
          @parcels,@errors = capture(@model)
          @signature = signature(@parcels)
          send_data
        rescue => error
          report(error.message)
        end
      end
      @dialog.add_action_callback('import_cad') do |_context|
        imported=false
        name=nil
        begin
          raise ArgumentError, '请退出组或组件编辑后导入' if Sketchup.active_model.active_path
          cad_status(state: 'choosing',message: '请选择 DWG 或 DXF 文件')
          path=UI.openpanel('选择 CAD 红线文件',nil,'CAD 文件|*.dwg;*.dxf||')
          unless path
            cad_status(state: 'cancelled',message: '已取消选择，原模型和上次导入保持原样')
            next
          end
          name=File.basename(path)
          cad_status(state: 'importing',name: name,message: '正在读取 CAD，请稍候…')
          target_model=Sketchup.active_model
          definition=CadImport.load_definition(target_model,path)
          instance=CadImport.place(target_model,definition,name,Geom::Transformation.new)
          @cad_instance=instance;@model=target_model;imported=true
          @cad_mode=false;@parcels=[];@errors=[];@signature=[]
          send_data
          info={name: name}
          begin
            info.merge!(CadImport.summary(instance))
          rescue => detail_error
            info[:warning]='图纸已导入，但几何统计未完成：'+detail_error.message
            info[:tags]=[]
          end
          begin
            CadImport.focus(@model,instance)
            info[:focused]=true
          rescue => focus_error
            info[:warning]=[info[:warning],'自动定位未完成：'+focus_error.message].compact.join('；')
          end
          @dialog.execute_script('cadLoaded('+JSON.generate(info)+')')
          report('CAD 已导入：'+name+'。请核对图纸尺寸，选择红线图层后识别。')
        rescue => error
          cad_status(state: imported ? 'warning' : 'failed',name: name,
            message: (imported ? 'CAD 已导入，后续显示遇到问题：' : 'CAD 导入失败：')+error.message)
          report(error.message)
        end
      end
      @dialog.add_action_callback('focus_cad') do |_context|
        begin
          raise ArgumentError, '请切回 CAD 导入所在模型' unless Sketchup.active_model == @model
          raise ArgumentError, '请退出组或组件编辑后定位图纸' if @model.active_path
          CadImport.focus(@model,@cad_instance)
          cad_status(state: 'focused',message: '已选中并缩放到导入图纸')
        rescue => error
          cad_status(state: 'failed',message: error.message)
        end
      end
      @dialog.add_action_callback('read_cad') do |_context,tag|
        begin
          @cad_tag=tag.to_s
          raise ArgumentError, '请选择红线图层' if @cad_tag.empty?
          @cad_mode=true
          @parcels,@errors=capture_cad
          @signature=signature(@parcels)
          send_data
        rescue => error
          @cad_mode=false;@parcels=[];@signature=[]
          send_data
          report('CAD 红线识别失败：'+error.message)
        end
      end
      @dialog.add_action_callback('generate') do |_context,payload|
        begin
          raise ArgumentError, '模型已经切换，请重新读取选择' unless Sketchup.active_model == @model
          current,_errors = @cad_mode ? capture_cad : capture(@model)
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

    def capture_cad
      raise ArgumentError, 'CAD 所在模型已切换' unless Sketchup.active_model == @model
      raise ArgumentError, '请退出组编辑，重新选择导入的 CAD 组件' if @model.active_path
      unless @cad_instance && @cad_instance.valid? && @model.selection.to_a == [@cad_instance]
        raise ArgumentError, 'CAD 组件选择已改变，请重新读取当前选择'
      end
      results,errors=[],[]
      scan([@cad_instance],Geom::Transformation.new,'CAD 红线',results,errors,0,@cad_tag)
      raise ArgumentError, '所选图层没有有效闭合地块。'+errors.join('；') if results.empty?
      raise ArgumentError, '单批最多 50 个地块，请分批处理' if results.length > 50
      results.each_with_index { |p,i| p[:id]=i.to_s;p[:name]='地块'+(i+1).to_s+' · '+p[:name] }
      [results,errors]
    end

    def cad_status(info)
      @dialog.execute_script('cadStatus('+JSON.generate(info)+')') if @dialog
    end

    def send_data
      @dialog.execute_script('receive(' + JSON.generate(parcels: @parcels, errors: @errors,backend_version: '0.2.6',cad_supported: true) + ')')
    end

    def report(message)
      @dialog.execute_script('report(' + JSON.generate(message) + ')') if @dialog
    end

    def numeric(value, positive = false)
      number = Float(value)
      raise ArgumentError, '数值须有限且非负；高度与层高须大于零' unless number.finite? && (positive ? number > 0 : number >= 0)
      number
    end

    def add_outline(entities,outline)
      points = outline.map { |p| Geom::Point3d.new(p[0]/INCH_TO_M,p[1]/INCH_TO_M,0) }
      face = entities.add_face(points)
      raise ArgumentError, 'SketchUp 无法创建范围面，请检查过短边' unless face
      face.reverse! if face.normal.z < 0
      face
    end

    def build_prism(container,outline,height,index)
      body = container.entities.add_group
      body.name = '闭合体量 ' + index.to_s
      mesh = Geometry.prism(outline,height)
      points = mesh[:points].map { |p| Geom::Point3d.new(*p.map { |v| v/INCH_TO_M }) }
      entities = body.entities
      mesh[:faces].each_with_index do |indices,face_index|
        face_points = indices.map { |i| points[i] }
        face = entities.add_face(face_points)
        raise ArgumentError, '无法创建体量封闭面，请检查过短边' unless face
        expected_normal = if face_index < 2
          Geom::Vector3d.new(0,0,face_index == 0 ? -1 : 1)
        else
          (face_points[1]-face_points[0]).cross(face_points[2]-face_points[0])
        end
        face.reverse! if face.normal.dot(expected_normal) < 0
      end
      edges = entities.grep(Sketchup::Edge)
      loose = edges.count { |e| e.faces.empty? }
      open = edges.count { |e| e.faces.length == 1 }
      multiple = edges.count { |e| e.faces.length > 2 }
      unless loose == 0 && open == 0 && multiple == 0 && SolidCheck.closed?(body)
        raise ArgumentError, format('体量闭合检查失败（游离边 %d / 开口边 %d / 多重边 %d），已取消此地块',loose,open,multiple)
      end
      expected_volume = Geometry.signed_area(outline)*height
      actual_volume = body.volume.to_f*INCH_TO_M**3
      if (actual_volume-expected_volume).abs > [0.001,expected_volume*1.0e-6].max
        raise ArgumentError, '生成体积与限高包络不一致，已取消此地块'
      end
      body
    end

    def prepared_outlines(source,setbacks,input)
      raise ArgumentError, '退线数量必须与原红线边数一致' unless setbacks.length == source[:points].length
      result = input['offset_result']
      if result
        method = result['method']
        raise ArgumentError, '偏移计算方式无效' unless ['parallel-miter','segment-clearance'].include?(method)
        if method == 'parallel-miter' && !setbacks.all? { |d| d == setbacks.first }
          raise ArgumentError, '统一退距结果与逐边参数不符'
        end
        outlines = result['outlines']
        unless outlines.is_a?(Array) && outlines.length <= 5000 &&
          outlines.all? { |ring| ring.is_a?(Array) && ring.length >= 3 && ring.length <= 10000 &&
            ring.all? { |p| p.is_a?(Array) && p.length == 2 && p.all? { |v| v.is_a?(Numeric) && v.finite? } } }
          raise ArgumentError, '偏移结果坐标或数量无效'
        end
        outlines.each { |ring| raise ArgumentError, '偏移结果方向无效' unless Geometry.signed_area(ring) > Geometry::AREA_EPS }
        Boundary.verify_outlines!(outlines,source[:points],setbacks)
        [outlines,method == 'parallel-miter' ? '尖角平行偏移' : '逐组最短退距圆角']
      else
        raise ArgumentError, input['offset_error'].to_s if input['offset_error']
        raise ArgumentError, '缺少本地偏移结果，请关闭插件并重新读取'
      end
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
          raise ArgumentError, '已识别内孔；当前体量算法尚不支持内孔，已跳过，避免填满内孔' unless source[:holes].empty?
          edge_labels = input['edge_labels'] || Array.new(source[:points].length,'未标注')
          unless edge_labels.is_a?(Array) && edge_labels.length == source[:points].length &&
            edge_labels.all? { |label| ['未标注','道路侧','邻地侧','其他'].include?(label) }
            raise ArgumentError, '边界用途标记与原边不匹配'
          end
          outlines,method = prepared_outlines(source,setbacks,input)
          cells = outlines
          name = input['name'].to_s.strip[0,100]
          name = source[:name] if name.empty?
          { source: source, height: height, floor_height: floor_height,
            cells: cells, outlines: outlines, setbacks: setbacks, name: name, method: method, edge_labels: edge_labels }
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
          origin = data[:source][:origin]
          group.transformation = Geom::Transformation.translation(origin.map { |v| v/INCH_TO_M })
          group.set_attribute(DICTIONARY,'generated',true)
          footprint = group.entities.add_group
          footprint.name = '可建范围（隐藏，展开组可显示）'
          data[:outlines].each { |outline| add_outline(footprint.entities,outline) }
          footprint.hidden = true
          volume = group.entities.add_group
          volume.name = '限高体量'
          data[:outlines].each_with_index { |outline,i| build_prism(volume,outline,data[:height],i+1) }
          volume.material = Sketchup::Color.new(92,160,176)
          floors = (data[:height]/data[:floor_height] + 1.0e-9).floor
          gfa = area*floors
          label = format("%s\n可建占地：%.2f ㎡\n限高：%.2f m · %d 层\n满铺估算建筑面积：%.2f ㎡\n层高：%.2f m · %s",
            data[:name],area,data[:height],floors,gfa,data[:floor_height],data[:method])
          anchor = Geom::Point3d.new(0,0,data[:height]/INCH_TO_M)
          group.entities.add_text(label,anchor)
          group.set_attribute(DICTIONARY,'parameters',JSON.generate(data.reject { |key,_| [:cells,:source,:outlines].include?(key) }))
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
