# encoding: UTF-8
# Usage: select exactly one parcel FACE (enter its group if needed), then
# load this script from SketchUp's Ruby Console. No model entities are changed.
require 'json'

parcel_model = Sketchup.active_model
parcel_faces = parcel_model.selection.grep(Sketchup::Face)
if parcel_faces.length != 1
  UI.messagebox('请只选中一个地块面。如果它在组内，请进入该组并单击选中面，再运行脚本。')
else
  parcel_face = parcel_faces.first
  parcel_transform = parcel_model.edit_transform
  parcel_scale = 0.0254
  parcel_loops = parcel_face.loops.map do |loop|
    {
      outer: loop.outer?,
      vertices_m: loop.vertices.map do |vertex|
        point = vertex.position.transform(parcel_transform)
        [point.x.to_f*parcel_scale,point.y.to_f*parcel_scale,point.z.to_f*parcel_scale]
      end
    }
  end
  parcel_data = {
    schema: 'buildable-envelope-parcel-v1',
    sketchup_version: Sketchup.version,
    units: 'meters',
    edge_count: parcel_face.edges.length,
    area_m2: parcel_face.area(parcel_transform)*parcel_scale**2,
    loops: parcel_loops,
    assumed_parameters: {
      uniform_setback_m: 5.0, height_m: 36.0, floor_height_m: 3.6,
      note: '诊断默认参数，请提供失败时实际使用的参数'
    }
  }
  parcel_path = UI.savepanel('导出诊断边界 JSON',nil,'parcel-boundary.json')
  if parcel_path
    parcel_path += '.json' unless File.extname(parcel_path).downcase == '.json'
    File.open(parcel_path,'w:UTF-8') { |file| file.write(JSON.pretty_generate(parcel_data)) }
    UI.messagebox("已导出地块边界，模型未修改。\n边数：" + parcel_face.edges.length.to_s + "\n路径：" + parcel_path)
  end
end
