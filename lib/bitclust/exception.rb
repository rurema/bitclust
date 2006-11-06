#
# bitclust/exception.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust
  class Error                   < StandardError; end
  class RequestError            < Error; end
  class NotInTransaction        < Error; end
  class ScanError               < Error; end
  class CompileError            < Error; end
  class WrongInclude            < CompileError; end
  class UserError               < Error; end
  class InvalidDatabase         < UserError; end
  class InvalidKey              < UserError; end
  class LibraryNotFound         < UserError; end
  class ClassNotFound           < UserError; end
  class MethodNotFound          < UserError; end
end
