require "active_support"
require "active_support/core_ext/module/delegation"
require "active_model"

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
  end

  self.allow_insecure_associations = false

  # {PermissionError} is raised when a security policy prevents
  # a called operation from being executed.
  class PermissionError < StandardError; end

  # {InsecureOperationError} is raised when a potentially unsafe
  # operation is about to be executed.
  class InsecureOperationError < StandardError; end

  # Heimdallr uses proxies to control access to restricted scopes and collections.
  module Proxy; end
end

require "heimdallr/proxy/collection"
require "heimdallr/proxy/record"
require "heimdallr/validator"
require "heimdallr/evaluator"
require "heimdallr/model"
require "heimdallr/legacy_resource"