module Heimdallr
  # A security-aware proxy for +ActiveRecord+ scopes. This class validates all the
  # method calls and either forwards them to the encapsulated scope or raises
  # an exception.
  class Proxy::Collection
    # Create a collection proxy.
    # @param context security context
    # @param object  proxified scope
    def initialize(context, scope)
      @context, @scope = context, scope

      @restrictions = @object.class.restrictions(context)
    end

    # Collections cannot be restricted twice.
    #
    # @raise [RuntimeError]
    def restrict(context)
      raise RuntimeError, "Collections cannot be restricted twice"
    end

    # Dummy method_missing.
    # @todo Write some actual dispatching logic.
    def method_missing(method, *args, &block)
      @scope.send method, *args
    end
  end
end