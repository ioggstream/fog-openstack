require "test_helper"
require "yaml"
require "open-uri"
require "fog/orchestration/util/recursive_hot_file_loader"  # FIXME is there a better way to require this file?

describe "Fog::Orchestration[:openstack] | stack requests" do
      @create_format_files = {
      'id'    => String,
      'links' => Array,
      'files' => Hash
    }
before do
    @orchestration = Fog::Orchestration[:openstack]

    @stack_format = {
      'links'               => Array,
      'id'                  => String,
      'stack_name'          => String,
      'description'         => Fog::Nullable::String,
      'stack_status'        => String,
      'stack_status_reason' => String,
      'creation_time'       => Time,
      'updated_time'        => Time
    }

    @stack_detailed_format = {
      "parent"                => Fog::Nullable::String,
      "disable_rollback"      => Fog::Boolean,
      "description"           => String,
      "links"                 => Array,
      "stack_status_reason"   => String,
      "stack_name"            => String,
      "stack_user_project_id" => String,
      "stack_owner"           => String,
      "creation_time"         => Fog::Nullable::String,
      "capabilities"          => Array,
      "notification_topics"   => Array,
      "updated_time"          => Fog::Nullable::String,
      "timeout_mins"          => Fog::Nullable::String,
      "stack_status"          => String,
      "parameters"            => Hash,
      "id"                    => String,
      "outputs"               => Array,
      "template_description"  => String
    }

    @create_format = {
      'id'    => String,
      'links' => Array,
    }

    @create_format_files = {
      'id'    => String,
      'links' => Array,
      'files' => Hash
    }

    @template = YAML.load(open("/code/test/requests/orchestration/template.yaml").read)
    
    @hot_resolver = Fog::Orchestration::Util::RecursiveHotFileLoader.new(@template)

  end

  describe "success" do
    it "#template_file_is_hot" do
      assert(true, @hot_resolver.is_hot(YAML.dump(@template)))
    end

    it "#get_content_locale" do
      content = @hot_resolver.get_content("/code/test/requests/orchestration/template.yaml")
      assert(true, content.include?("heat_template_version"))
    end

    it "#get_content_remote" do
      content = @hot_resolver.get_content("https://www.google.com/robots.txt")
      puts content
      assert(true, content.include?("heat_template_version"))
    end

    it "#get_content_404" do  # FIXME
      assert_raise OpenURI::HTTPError do
        content = @hot_resolver.get_content("https://www.google.com/NOOP")
      end
    end


    it "#create_stack_with_files" do
      args = {
        :stack_name => "teststack_files", 
        :files => {'foo.sh' => 'hello'}
      }
      @stack = @orchestration.create_stack(args).body.must_match_schema(@create_format_files)
    end

    it "#create_stack_resolve_files" do
      args = {
        :stack_name => "teststack_files", 
        :template => YAML.load(open("/code/test/requests/orchestration/template.yaml").read)
      }
      @stack = @orchestration.create_stack(args).body.must_match_schema(@create_format_files)
    end

  end
end
