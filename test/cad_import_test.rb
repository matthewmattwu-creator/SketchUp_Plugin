require 'minitest/autorun'
require 'tempfile'
require_relative '../src/buildable_envelope/cad_import'
class CadImportTest < Minitest::Test
  C=MattWu::BuildableEnvelope::CadImport
  Definition=Struct.new(:entities) do
    def valid?; true; end
  end
  class Definitions
    attr_reader :received
    def initialize(result);@result=result;end
    def import(path,options);@received=[path,options];@result;end
  end
  class Selection < Array
    def add(entity);self << entity;end
  end
  class Instance
    attr_accessor :name
    def valid?;true;end
  end
  class Entities
    attr_reader :args
    def initialize(fail=false);@fail=fail;end
    def add_instance(definition,transformation);raise 'placement failure' if @fail;@args=[definition,transformation];Instance.new;end
  end
  class Model
    attr_reader :selection,:entities,:events
    def initialize(fail=false);@selection=Selection.new;@entities=Entities.new(fail);@events=[];end
    def active_path;nil;end
    def start_operation(*);@events << :start;end
    def commit_operation;@events << :commit;end
    def abort_operation;@events << :abort;end
  end
  def test_imports_definition_with_documented_dwg_options
    file=Tempfile.new(['redline','.dwg'])
    begin
      definition=Definition.new([:geometry]);definitions=Definitions.new(definition)
      model=Struct.new(:definitions).new(definitions)
      assert_equal definition,C.load_definition(model,file.path)
      assert_equal file.path,definitions.received[0]
      assert_equal true,definitions.received[1][:preserve_origin]
      assert_equal false,definitions.received[1][:merge_coplanar_faces]
      refute definitions.received[1].key?(:units)
      assert_equal false,definitions.received[1][:show_summary]
    ensure
      file.close!
    end
  end
  def test_rejects_wrong_extension_and_missing_file
    assert_raises(ArgumentError){C.validate_path('redline.txt')}
    assert_raises(ArgumentError){C.validate_path('missing-never-present.dxf')}
  end
  def test_failed_native_import_is_not_placed
    file=Tempfile.new(['redline','.dxf'])
    begin
      assert_raises(ArgumentError){C.load_definition(Struct.new(:definitions).new(Definitions.new(nil)),file.path)}
    ensure
      file.close!
    end
  end
  def test_places_isolated_instance_without_replacing_existing_geometry
    model=Model.new;old=Instance.new;model.selection.add(old);definition=Definition.new([:geometry])
    result=C.place(model,definition,'redline.dwg',:identity)
    assert_equal [definition,:identity],model.entities.args
    assert_equal [result],model.selection
    assert_equal 'redline.dwg',result.name
    assert_equal [:start,:commit],model.events
  end
  def test_failed_placement_restores_selection
    model=Model.new(true);old=Instance.new;model.selection.add(old)
    assert_raises(RuntimeError){C.place(model,Definition.new([:geometry]),'redline.dwg',:identity)}
    assert_equal [old],model.selection
    assert_equal [:start,:abort],model.events
  end
end

class CadFocusTest < Minitest::Test
  C=MattWu::BuildableEnvelope::CadImport
  class View
    attr_reader :zoomed
    def zoom(instance);@zoomed=instance;end
  end
  def test_focus_selects_only_the_imported_instance_and_zooms_it
    selection=CadImportTest::Selection.new;selection.add(:old)
    view=View.new
    model=Struct.new(:selection,:active_view).new(selection,view)
    instance=CadImportTest::Instance.new
    assert C.focus(model,instance)
    assert_equal [instance],selection
    assert_equal instance,view.zoomed
  end
  def test_invalid_instance_does_not_change_selection
    selection=CadImportTest::Selection.new;selection.add(:old)
    instance=Object.new;def instance.valid?;false;end
    assert_raises(ArgumentError){C.focus(Struct.new(:selection,:active_view).new(selection,View.new),instance)}
    assert_equal [:old],selection
  end
end
