require "test_helper"
require "yaml"
require "open-uri"
require "fog/orchestration/util/recursive_hot_file_loader"  # FIXME: is there a better way to require this file?

describe "Fog::Orchestration[:openstack] | stack requests" do
  @create_format_files = {
    'id'    => String,
    'links' => Array,
    'files' => Hash
  }
  before do
    @orchestration = Fog::Orchestration[:openstack]

    @data = YAML.safe_load(open("test/requests/orchestration/stack_files_util_tests.yaml"))
    @template_yaml = YAML.safe_load(open("test/requests/orchestration/template.yaml"))
    @local_yaml = YAML.safe_load(open("test/requests/orchestration/local.yaml"))

    @hot_resolver = Fog::Orchestration::Util::RecursiveHotFileLoader.new(@template_yaml)

    @base_url = URI.join("file:", File.absolute_path("test/requests/orchestration/"))
    @base_url.host = ""  # fix
  end

  describe "success" do
    it "#template_file_is_hot" do
      assert(true, @hot_resolver.is_template(YAML.dump(@template_yaml)))
    end

    it "#get_content_locale" do
      content = @hot_resolver.get_content("test/requests/orchestration/template.yaml")
      assert_includes(content, "heat_template_version")
    end

    it "#get_content_remote" do
      content = @hot_resolver.get_content("https://www.google.com/robots.txt")
      assert_includes(content, "Disallow:")
    end

    it "#get_content_404" do  # FIXME
      assert_raises OpenURI::HTTPError do
        @hot_resolver.get_content("https://www.google.com/NOOP")
      end
    end

    it "#base_url_for_url" do
      test_cases = [
        ["file:///f.txt", "file:///"],
        ["file:///a/f.txt", "file:///a"],
        ["file:///a/b/f.txt", "file:///a/b"],
        ["http://h.com/a/f.txt", "http://h.com/a"],
        ["https://h.com/a/b/f.txt", "https://h.com/a/b"],
      ]
      test_cases.each do |data, expected|
        assert_equal(@hot_resolver.base_url_for_url(data).to_s, expected)
      end
    end

    it "#get_file_contents_simple" do
      test_cases = [
        ["a string", {}],
        [["a", "list"], {}],
        [{"a" => "dict", "b" => "values"}, {}],
        [{"type"=>"OS::Nova::Server"}, {}],
        [{"get_file" => "test/requests/orchestration/foo.sh", "b" => "values"}, {'test/requests/orchestration/foo.sh'=>'# Just a mock'}],
        # [{"get_file"=>"test/requests/orchestration/template.yaml","b"=>"values"}, ""],
      ]
      test_cases.each do |data, expected|
        hot_resolver = Fog::Orchestration::Util::RecursiveHotFileLoader.new(@template_yaml)
        hot_resolver.get_file_contents(data)
        Fog::Logger.warning("Processed files: #{hot_resolver.files}")
        assert_equal(hot_resolver.files, expected)
      end
    end

    it "#get_file_contents_references_template" do
      # Heat files parameter is populated with URI-like syntax. The expected
      #  values are absolute paths uri and should be resolved with the local
      #  directory.

      test_cases = [
        [{"type"=>"local.yaml"}, ["local.yaml", "hot_1.yaml"]],
        [{"type"=>"no_recursion.yaml"}, ["no_recursion.yaml"]],
        [{"type"=>"local_fullpath.yaml"}, ["local_fullpath.yaml", "local.yaml", "hot_1.yaml"]],
      ]
      test_cases.each do |data, expected|
        expected = prefix_with_url(expected, @base_url)
        hot_resolver = Fog::Orchestration::Util::RecursiveHotFileLoader.new(@template_yaml)
        hot_resolver.get_file_contents(data, base_url = @base_url.to_s)
        Fog::Logger.warning("Processed files: #{hot_resolver.files}")
        assert_equal(hot_resolver.files.keys, expected)
      end
    end

    it "#get_file_contents_http_template" do
      test_cases = @data["get_file_contents_http_template"].map do |testcase|
        #    [ testcase['input'], testcase['expected'] ]
      end.compact
      test_cases.each do |data, expected|
        hot_resolver = Fog::Orchestration::Util::RecursiveHotFileLoader.new(@template_yaml)
        hot_resolver.get_file_contents(data)
        Fog::Logger.warning("Processed files: #{hot_resolver.files.keys}")
        assert_equal_set(hot_resolver.files.keys, expected)
      end
    end

    it "#recurse_template" do
      Dir.chdir("test/requests/orchestration") do
        hot_resolver = Fog::Orchestration::Util::RecursiveHotFileLoader.new(@local_yaml)
        files = hot_resolver.get_files
        Fog::Logger.warning("Processed files: #{files.keys}")
        assert_equal_set(files.keys, prefix_with_url(["local.yaml", "hot_1.yaml"], @base_url))
      end
    end

    it "#modify_template" do
      Dir.chdir("test/requests/orchestration") do
        hot_resolver = Fog::Orchestration::Util::RecursiveHotFileLoader.new(@local_yaml)
        hot_resolver.get_files
        template = hot_resolver.template

        # The template argument should be modified.
        assert(template['resources']['a_file']['type'].start_with?('file:///'))

        # No side effect on the original template.
        assert(!@local_yaml['resources']['a_file']['type'].start_with?('file:///'))
      end
    end
  end
end
