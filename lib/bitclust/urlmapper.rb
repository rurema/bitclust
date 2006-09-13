#
# bitclust/urlmapper.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust

  class URLMapper
    def initialize(baseurl)
      @url = baseurl
    end

    attr_reader :url

    def drift
      @url
    end

    def view(id)
      "#{@url}?#{id}"
    end

    def edit(id)
      "#{@url}?e#{id}"
    end

    def create
      "#{@url}?c"
    end

    def write(id)
      "#{@url}?w#{id}"
    end
  end

end
