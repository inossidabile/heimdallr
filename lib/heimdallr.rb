require "active_support"
require "active_model"

require "heimdallr/version"

require "heimdallr/evaluator"
require "heimdallr/proxy"
require "heimdallr/model"
require "heimdallr/resource"

module Heimdallr
  # {PermissionError} is raised in all contexts where a security policy prevents
  # a called operation from being executed.
  class PermissionError < StandardError; end
end