module Heimdallr
  module Model
    extend ActiveSupport::Concern

    module ClassMethods
      def restrict(&block)
        @restrictions = Evaluator.new(self, &block)
      end

      def restricted?
        !@restrictions.nil?
      end

      def restrictions(context)
        @restrictions.evaluate(context) if @restrictions
      end
    end

    module InstanceMethods
      def to_proxy(context, action)
        if self.class.restricted?
          Proxy.new(context, action, self)
        else
          self
        end
      end

      def validate_action(context, action)
        if self.class.restricted?
          self.class.restrictions(context).validate(action, self)
        end
      end
    end
  end
end