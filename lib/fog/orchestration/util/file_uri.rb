# Ruby URI is not round-trip safe when schema == file
#  eg. URI("file:///a.out").to_s != file:///a.out"
module URI
  class FILE < Generic
    def to_s
      super.to_s.sub(%r{^file:\/+}, "file:///")
    end
  end
  @@schemes['FILE'] = FILE
end
