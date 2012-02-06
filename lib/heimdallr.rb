require "active_support"
require "active_model"

require "heimdallr/version"

require "heimdallr/proxy/collection"
require "heimdallr/proxy/record"
require "heimdallr/validator"
require "heimdallr/evaluator"
require "heimdallr/model"
require "heimdallr/resource"

# See {file:README.yard}.
module Heimdallr
  class << self
    # Allow implicit insecure association access. Consider this code:
    #
    #     class User < ActiveRecord::Base
    #       include Heimdallr::Model
    #
    #       has_many :articles
    #     end
    #
    #     class Article < ActiveRecord::Base
    #       # No Heimdallr::Model!
    #     end
    #
    # If the +allow_insecure_associations+ setting is +false+ (the default),
    # then +user.restrict(context).articles+ fetch would cause an
    # {InsecureOperationError}. This may be undesirable in some environments;
    # setting +allow_insecure_associations+ to +true+ will prevent the error
    # from being raised.
    #
    # @return [Boolean]
    attr_accessor :allow_insecure_associations
    self.allow_insecure_associations = false
  end

  # {PermissionError} is raised when a security policy prevents
  # a called operation from being executed.
  class PermissionError < StandardError; end

  # {InsecureOperationError} is raised when a potentially unsafe
  # operation is about to be executed.
  class InsecureOperationError < StandardError; end
end