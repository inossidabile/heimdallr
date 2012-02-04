module Heimdallr
  class Proxy::Record
    # Create a record proxy.
    # @param          context security context
    # @param [Symbol] action  kind of actions which will be performed
    # @param          object  proxified record
    def initialize(context, action, object)
      @context, @action, @object = context, action, object

      restrictions = @object.class.restrictions(context)
      @whitelist = restrictions.whitelist[@action]
    end

    # Remove non-whitelisted attributes.
    # @macro [new] attributes
    #   @param [Hash]  attributes attribute hash
    #   @param [Array] whitelist  permitted attributes
    #   @return [Hash] safe attributes
    def self.filter_attributes(attributes, whitelist)
      attributes.delete_if do |key, value|
        !whitelist.include?(key)
      end

      attributes
    end

    # Raise an error if non-whitelisted attribute is set.
    # @macro [attached] attributes
    # @raise [Heimdallr::PermissionError]
    def self.filter_attributes!(attributes, whitelist)
      attributes.keys.each do |key|
        unless whitelist.include? key
          raise Heimdallr::PermissionError,
              "non-whitelisted attribute #{key} is provided for #{@object.inspect} on #{@action}"
        end
      end

      attributes
    end

    # Whitelisting proxy for the +attributes+ method.
    def attributes
      self.class.filter_attributes(@object.attributes, @whitelist)
    end

    # Whitelisting proxy for the +update_attributes+ method.
    # All non-whitelisted attributes are silently removed.
    def update_attributes(attributes)
      @object.attributes = self.class.filter_attributes(attributes, @whitelist)
    end

    # Whitelisting proxy for the +update_attributes!+ method.
    # All non-whitelisted attributes are silently removed.
    def update_attributes!(attributes)
      @object.update_attributes!(self.class.filter_attributes(attributes, @whitelist))
    end

    # A whitelisting dispatcher for attribute-related method calls.
    # Every unknown method is first normalized (that is, stripped of its +?+ or +=+
    # suffix). Then, if the normalized form is whitelisted, it is passed to the
    # underlying object as-is. Otherwise, an exception is raised.
    #
    # If the underlying object is an instance of ActiveRecord, then all association
    # accesses are resolved and proxified automatically.
    #
    # Note that only the attribute and collection getters and setters are
    # dispatched through this method. Every other model method should be defined
    # as an instance method of this class in order to work.
    #
    # @raise [Heimdallr::PermissionError] when a non-whitelisted method is accessed
    def method_missing(method, *args)
      if method.to_s.ends_with?("?") || method.to_s.ends_with?("=")
        normalized_method = method[0..-2].to_sym
      else
        normalized_method = method
      end

      if defined?(ActiveRecord) && @object.is_a?(ActiveRecord::Base) &&
          association = @object.class.reflect_on_association(method)
        if association.collection?
          raise NotImplementedError
        else
          referenced = @object.send(method, *args)
          if referenced.respond_to? :to_proxy
            referenced.to_proxy(@context, @action)
          else
            referenced
          end
        end
      elsif @whitelist.include? normalized_method
        @object.send method, *args
      elsif @object.respond_to? method
        raise Heimdallr::PermissionError,
            "non-whitelisted method #{method} is called for #{@object.inspect} on #{@action}"
      else
        super
      end
    end

    # Describes the proxy and proxified object.
    # @return [String]
    def inspect
      "#<Heimdallr::Proxy(#{@action}): #{@object.inspect}>"
    end

    # Return the associated security metadata. The returned hash will contain keys
    # +:context+, +:action+ and +:object+, corresponding to the parameters in
    # {#initialize}.
    #
    # Such a name was deliberately selected for this method in order to reduce namespace
    # pollution.
    #
    # @return [Hash]
    def reflect_on_security
    end
  end
end