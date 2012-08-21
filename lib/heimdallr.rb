require "active_support"
require "active_support/core_ext/module/delegation"
require "active_model"
require "orm_adapter"

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

    # Allow unrestricted association fetching in case of eager loading.
    #
    # By default, associations are restricted with fetch scope either when
    # they are accessed or when they are eagerly loaded (with #includes).
    # Condition injection on eager loads are known to be quirky in some cases,
    # particularly deeply nested polymorphic associations, and if the layout
    # of your database guarantees that any data fetched through explicitly
    # eagerly loaded associations will be safe to view (or if you restrict
    # it manually), you can enable this setting to skip automatic condition
    # injection.
    #
    # @return [Boolean]
    attr_accessor :skip_eager_condition_injection
  end

  self.allow_insecure_associations = false
  self.skip_eager_condition_injection = false

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
