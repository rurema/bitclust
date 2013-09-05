#
# bitclust/exception.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust
  class Error                   < StandardError; end
  class RequestError            < Error; end
  class NotInTransaction        < Error; end
  class DocumentError           < Error; end
  class ScanError               < DocumentError; end
  class ParseError              < DocumentError; end
  class WrongInclude            < DocumentError; end
  class InvalidLink             < DocumentError; end
  class InvalidAncestor         < DocumentError; end
  class UserError               < Error; end
  class InvalidDatabase         < UserError; end
  class InvalidKey              < UserError; end
  class InvalidScheme           < UserError; end
  class NotFoundError           < UserError; end
  class LibraryNotFound         < NotFoundError; end
  class ClassNotFound           < NotFoundError; end
  class MethodNotFound          < NotFoundError; end
  class FunctionNotFound        < NotFoundError; end
  class DocNotFound             < NotFoundError; end

  module WriterError; end
  class DocumentError
    include WriterError
  end
  class UserError
    include WriterError
  end
end
