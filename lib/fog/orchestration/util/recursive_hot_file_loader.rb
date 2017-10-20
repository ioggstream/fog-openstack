require 'yaml'
require 'open-uri'
require 'objspace'
require 'fog/core'
require 'set'
require 'fog/orchestration/util/file_uri'

module Fog
  module Orchestration
    module Util
      #
      # Resolve get_file resources found in a HOT template populating
      #  a files Hash conforming to Heat Specs
      #  https://developer.openstack.org/api-ref/orchestration/v1/index.html?expanded=create-stack-detail#stacks
      #
      # Passed :files are not processed further.
      #
      # This implementation just process nested templates but not resource
      #  registries.
      class RecursiveHotFileLoader
        attr_reader :files
        attr_reader :template
        attr_reader :template_ori
        attr_reader :visited
        attr_reader :max_files_size

        def initialize(template, files = nil)
          @template = template
          @template_ori = template
          @template_base_url = nil
          @files = files || {}
          @max_files_size = (128 * 1 << 10)
          @visited = {}
        end

        def yaml_load(content)
          return YAML.load(content) if RUBY_VERSION < "2.1"

          YAML.safe_load(content, [Date])
        end

        def get_files
          Fog::Logger.warning("Processing template #{@template}")
          _, @template = get_template_contents(@template)
          Fog::Logger.warning("Template processed. Populated #{@files}")
          @files
        end

        def files_basepath
          min_lenght = @files.keys.map(&:length).min
          candidates = @files.keys.map { |x| File.dirname(x[0..min_lenght]) }.to_set
          return nil if candidates.size != 1
          candidates.each do |x|
            return x
          end
        end

        def template_is_raw?(content)
          # Return true if the file is an heat template, false otherwise.
          htv = content.index("heat_template_version:")
          !!(htv && htv < 5)
        end

        def template_is_url?(path)
          # return true if it's an URI, false otherwise.
          normalise_file_path_to_url(path)
          return true
        rescue ArgumentError, URI::InvalidURIError
          return false
        end

        def file_outside_base_url(base_url, str_url)
          ret = base_url && str_url.start_with?("file://") && !str_url.start_with?(base_url)
          if ret
            Fog::Logger.warning("Trying to reference a file outside #{base_url}: #{str_url}")
          end
          ret
        end

        def ignore_if(key, value)
          # Should I attach this file?
          return true if key != 'get_file' && key != 'type'

          return true unless value.kind_of?(String)

          return true if key == 'type' &&
                         !value.end_with?('.yaml', '.template')

          false
        end

        def recurse_if(value)
          # Should I recurse into this template branch?
          value.kind_of?(Hash) || value.kind_of?(Array)
        end

        def url_join(prefix, suffix)
          # return string
          if prefix
            suffix = URI.join(prefix, suffix)
            suffix = suffix.to_s
          end
          suffix
        end

        def base_url_for_url(url)
          # Returns the string baseurl of the given url.
          parsed = URI(url)
          parsed_dir = File.dirname(parsed.path)
          URI.join(parsed, parsed_dir).to_s
        end

        def normalise_file_path_to_url(path)
          # Nothing to do on URIs
          return path if URI(path).scheme

          path = File.absolute_path(path)
          url_join('file:/', path)
        end

        def get_content(uri_or_filename)
          Fog::Logger.warning("Opening #{uri_or_filename}")
          uri_or_filename = uri_or_filename.to_s if uri_or_filename.kind_of?(URI)
          # throw exceptions enables stack creation to fail
          #   with a suitable error.
          #
          # XXX Implement a retry here?
          content = ''
          # does ruby close the socket/filedescriptor at exit?
          # XXX Limit download file size
          # XXX Protect from vanilla open-uri attacks
          uri_or_filename = uri_or_filename[7..-1] if uri_or_filename.start_with?("file:///")
          open(uri_or_filename) { |f| content = f.read }
          content == "Error" ? nil : content

          content
        end

        def get_template_contents(template_file)
          # Same code for both template_file and template_url.
          Fog::Logger.warning("get_template_contents #{template_file}")

          local_base_url = base_url_for_url(normalise_file_path_to_url(Dir.pwd + "/TEMPLATE"))

          raise NotImplementedError, "template_file should be Hash or String" unless
            template_file.kind_of?(String) || template_file.kind_of?(Hash)

          if template_file.kind_of?(Hash)
            template_base_url = local_base_url
            raw_template = YAML.dump(template_file)
          elsif template_is_raw?(template_file)
            raw_template = template_file
            template_base_url = local_base_url
          elsif template_is_url?(template_file)
            template_file = normalise_file_path_to_url(template_file)
            template_base_url = base_url_for_url(template_file)
            raw_template = get_content(template_file)
            @visited[template_file] = true
            Fog::Logger.warning("Template visited: #{@visited}")
          else
            raise NotImplementedError, "template_file is not a string of the expected form"
          end
          template = yaml_load(raw_template)

          get_file_contents(template, template_base_url)

          return nil, template
        end

        def get_file_contents(from_data, base_url = nil)
          Fog::Logger.warning("Processing #{from_data} with base_url #{base_url}")

          if recurse_if(from_data)
            recurse_data = from_data.kind_of?(Hash) ? from_data.to_a : from_data
            recurse_data.each do |value|
              get_file_contents(value, base_url)
            end
          end

          # Actually processing data.
          if from_data.kind_of?(Hash)
            from_data.each do |key, value|
              next if ignore_if(key, value)
              Fog::Logger.debug("Inspecting #{key}, #{value} at #{base_url}")

              # Resolve relative paths.
              base_url += '/' if base_url && !base_url.end_with?('/')
              str_url = url_join(base_url, value)

              next if @files.key?(str_url)
              # Don't process file:// outside our base_url. TODO raise an exception here?
              next if file_outside_base_url(base_url, str_url)

              file_content = get_content(str_url)

              # get_file should not recurse hot templates.
              if key == "type" && template_is_raw?(file_content) && !(@visited[str_url])
                template = get_template_contents(str_url)[1]
                file_content = YAML.dump(template)
              end
              @files[str_url] = file_content
              # replace the data value with the normalised absolute URL
              Fog::Logger.warning("Replacing #{key} with #{str_url} in #{from_data}")
              from_data[key] = str_url
            end
          end
        end
      end # Class
    end
  end
end
