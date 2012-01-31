module Heimdallr
  class Proxy
    def initialize(context, action, object)
      @context, @action, @object = context, action, object

      @whitelist = @object.class.restrictions(context).whitelist[@action]
    end

    def self.filter_attributes(attributes, whitelist)
      attributes.delete_if do |key, value|
        !whitelist.include?(key)
      end

      attributes
    end

    def attributes
      self.class.filter_attributes(@object.attributes, @whitelist)
    end

    def update_attributes(attributes)
      @object.update_attributes(self.class.filter_attributes(attributes, @whitelist))
    end

    def update_attributes(attributes)
      @object.update_attributes!(self.class.filter_attributes(attributes, @whitelist))
    end

    def method_missing(method, *args)
      if method.to_s.ends_with?("?") || method.to_s.ends_with?("=")
        normalized_method = method[0..-2].to_sym
      else
        normalized_method = method
      end

      if defined?(ActiveRecord) && @object.is_a?(ActiveRecord::Base) &&
          association = @object.class.reflect_on_association(method)
        if association.collection?
          raise "not implemented"
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
        nil
      else
        super
      end
    end

    def inspect
      "#<Heimdallr::Proxy(#{@whitelist.join ", "}): #{@object.inspect}>"
    end
  end
end