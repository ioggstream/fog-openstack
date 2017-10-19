require 'yaml'
require 'open-uri'
require 'objspace'
require 'fog/core'
require 'set'

module Fog
  module Orchestration
    module Util
      #
      # Resolve get_file resources found in a HOT template populating
      #  a files Hash conforming to Heat Specs
      #  https://developer.openstack.org/api-ref/orchestration/v1/index.html?expanded=create-stack-detail#stacks
      # 
      # This implementation just process nested templates but not resource
      #  registries.
      class RecursiveHotFileLoader
        attr_reader :files
        attr_reader :template
        attr_reader :visited
        attr_reader :max_files_size
        
        def initialize(template)
          @template = template
          @template_base_url = nil
          @files = {}
          @max_files_size = (128 * 1<<10)
          @visited = {}
        end
        
        def get_files()
          Fog::Logger.warning("Processing template #{@template}")
          self.get_file_contents(@template, base_url=normalise_file_path_to_url(Dir.pwd()))
          Fog::Logger.warning("Template processed")
          return @files
        end

        def files_basepath()
          min_lenght = @files.keys().map {|x| x.length}.min
          candidates = @files.keys().map {|x| File.dirname(x[0..min_lenght])}.to_set
          return nil if candidates.size != 1
          candidates.each { |x|
            return x
          }
        end

        def is_template(content)
          # Return true if the file is an heat template, false otherwise.
          htv = content.index("heat_template_version:") 
          return !!(htv and htv < 5)
        end
       
        def fixup_uri(uri)
          # Ruby URI is not round-trip safe when schema == file
          #  eg. URI("file:///a.out").to_s != file:///a.out"
          if uri.kind_of?(URI) and uri.scheme == "file"
            uri.host = ""
          end 
          return uri
        end

        def ignore_if(key, value)
          # Should I attach this file?
          return true if key != 'get_file' and key != 'type'
            
          return true if not value.kind_of?(String)

          return true if (key == 'type' and
            not value.end_with?('.yaml', '.template'))

          return false
        end
        
        def recurse_if(value)
          # Should I recurse into this template branch?
          return !!(value.kind_of?(Hash) or value.kind_of?(Array))
        end

        def url_join(prefix, suffix)
          # return string
          if prefix
            suffix = URI.join(prefix, suffix)
            fixup_uri(suffix)
            suffix = suffix.to_s
          end
          return suffix
        end

        def base_url_for_url(url)
          # Returns the string baseurl of the given url.
          parsed = URI(url)
          # Ruby URI is not round-trip safe when schema == file
          fixup_uri(parsed)
          parsed_dir = File.dirname(parsed.path)
          return URI.join(parsed, parsed_dir).to_s
        end
        
        def normalise_file_path_to_url(path)
          # Nothing to do on URIs
          return path if URI(path).scheme
          
          path = File.absolute_path(path)
          return url_join('file:', path)
        end

        def get_content(uri_or_filename)
          Fog::Logger.warning("Opening #{uri_or_filename}")
          uri_or_filename = fixup_uri(uri_or_filename)
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
          
          return content
        end
        
        def get_template_contents(template_file, template_url=nil, template_object=nil, existing=false)
          Fog::Logger.warning("get_template_contents #{template_file}")
          
          # in Fog, template is always an object
          is_object = false

          template_file = normalise_file_path_to_url(template_file)
          template_base_url = base_url_for_url(template_file)
          # TODO normalize template_file
          tpl = self.get_content(template_file)
          template = YAML.load(tpl)

          @visited[template_file] = true
          Fog::Logger.warning("Template visited: #{@visited}")
          self.get_file_contents(template, base_url=template_base_url)

          return nil, template

        end
  
        def get_file_contents(from_data, base_url=nil, is_object=false, object_request=nil)
          Fog::Logger.debug("Processing #{from_data} with base_url #{base_url}")
          
          if recurse_if(from_data)
            if from_data.kind_of?(Hash)
              recurse_data = from_data.to_a
            else
              recurse_data = from_data
            end
            
            recurse_data.each { |value|
              get_file_contents(value, base_url=base_url)
            }
          end

          # Actually processing data.
          if from_data.kind_of?(Hash)
            from_data.each{ |key, value |
              next if ignore_if(key, value)
              Fog::Logger.warning("Inspecting #{key}, #{value} at #{base_url}")
              
              # Resolve relative paths.
              if base_url and not base_url.end_with?('/')
                base_url += '/'
              end

              str_url = url_join(base_url, value)
              if not @files.has_key?(str_url)
              
                # Don't process files outside our base_url.
                if base_url and not str_url.start_with?(base_url)
                  Fog::Logger.warning("Trying to reference a file outside #{base_url}: #{str_url}")
                  next
                end
            
                if is_object and object_request
                    raise NotImplementedError
                    file_content = object_request('GET', str_url)
                else
                    file_content = self.get_content(str_url)
                end

                # get_file should not recurse hot templates.
                if key == "type" and is_template(file_content) and not @visited[str_url]
                    if is_object
                        raise NotImplementedError
                        template = self.get_template_contents(
                            template_object=str_url,
                            object_request=object_request)[1]
                    else
                        template = self.get_template_contents(
                            template_url=str_url)[1]
                    end
                    file_content = YAML.dump(template)
                end
                @files[str_url] = file_content
              # replace the data value with the normalised absolute URL
              from_data[key] = str_url
              end
            }
          end
        end
      end # Class 
    end
  end
end

