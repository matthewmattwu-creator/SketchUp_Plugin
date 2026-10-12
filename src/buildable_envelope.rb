# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'
module MattWu
  module BuildableEnvelope
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('可建体量快速生成', 'buildable_envelope/main')
      extension.description = '逐边退线、限高、批量体量与几何容量估算'
      extension.version = '0.2.6'
      extension.creator = 'matthewmattwu-creator'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
