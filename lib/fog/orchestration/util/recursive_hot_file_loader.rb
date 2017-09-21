require 'yaml'
require 'open-uri'
require 'objspace'

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
                
                def initialize(template)
                    @template = template
                    @files = {}
                    @max_files_size = (128 * 1<<10)
                    @visited = {}
                end
                
                def is_hot(content)
                    htv = content.index("heat_template_version:") 
                    return !!(htv and htv < 5)
                end
                
                def traverse(obj, parent, &blk)  # FIXME: eventually limit the total file size 
                    case obj
                        when Hash
                        # Forget keys because I don't know what to do with them
                            obj.each {|k,v| traverse(v, k, &blk) }
                        when Array
                            obj.each {|v| traverse(v, parent, &blk) }
                        else
                            blk.call(obj, parent)
                    end
                end
                
                def get_content(uri_or_filename)
                    # throw exceptions enables stack creation to fail
                    #   with a suitable error. 
                    # 
                    # XXX Implement a retry here?
                    content = ''
                    # does ruby close the socket/filedescriptor at exit?
                    # XXX Limit download file size
                    # XXX Protect from vanilla open-uri attacks
                    open(uri_or_filename) { |f| content = f.read }
                    content == "Error" ? nil : content
                    
                    return content
                end
                
                def process_file(filename)
                    # No infinite loops.
                    return if @visited.key?(filename) or @files.key?(filename)

                    # Process only HOT files
                    content = self.get_content(filename)
                    return if not self.is_hot(content)
                  
                    # Preserve memory
                    if ObjectSpace.memsize_of(@files) < @max_files_size
                        raise NotImplementedError
                    end

                    puts "New heat file #{filename}"
                    ret = YAML.load(content)
                  
                    # I can parse this node, mark it as visited!
                    # XXX a visited filename could be referenced by a 
                    #  future get_file so consider removing the @visited
                    #  feature.
                    @visited[filename] = 1
                    traverse(ret, nil) do |node, parent|
                      # Files and templates are always strings
                      next if not node.kind_of?(String)
                  
                      if parent == 'type' 
                        # Process nested templates (it's a kludge but works)
                        #  we should actually check that 'type' is the resource 
                        #  type. Probably Heat is able to resolve nested resources
                        #  without adding them.
                        if File.exists?(node) or node.start_with?("http")
                          files[filename] = content
                          process_file(node, h, files) 
                        end
                      elsif parent == 'get_file'
                        # Process plain files
                        puts "match #{parent}: #{node}"
                        files[filename] = get_content(node)
                      else
                        # Debug unmatching entries
                        puts "Unmatch #{parent}: #{node}"
                      end
                    end
                  end
                  
                def ignore_if(key, value)
                    if key != 'get_file' and key != 'type':
                        return true
                    if not value.kind_of?(String):
                        return true
                    if (key == 'type' and
                            not value.end_with?('.yaml', '.template')):
                        return true
                    return false
                end


            end
        end
    end
end