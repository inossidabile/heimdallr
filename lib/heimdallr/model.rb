module Heimdallr
  module Model
    extend ActiveSupport::Concern

    module ClassMethods
      # @overload restrict
      #   Define restrictions for a model with a DSL. See {Model} overview
      #   for DSL documentation.
      #   @yield A passed block is executed in the context of a new {Evaluator}.
      #
      # @overload restrict(context, action=:view)
      #   Return a secure collection object for the current scope.
      #   @param [Object] context security context
      #   @param [Symbol] action  kind of actions which will be performed
      #   @return [Proxy::Collection]
      def restrict(context=nil, action=:view, &block)
        if block
          @restrictions = Evaluator.new(self, &block)
        else
          Proxy::Collection.new(context, action, self)
        end
      end

      # Evaluate the restrictions for a given context.
      # @return [Evaluator]
      def restrictions(context)
        @restrictions.evaluate(context)
      end
    end

    # Return a secure proxy object for this record.
    # @return [Record::Proxy]
    def restrict(context, action)
      Record::Proxy.new(context, action, self)
    end
  end
end