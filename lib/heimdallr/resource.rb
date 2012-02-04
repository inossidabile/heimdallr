module Heimdallr
  # Heimdallr {Resource} is a boilerplate for simple creation of REST endpoints, most of which are
  # quite similar and thus may share a lot of code.
  #
  # The minimal controller possible would be:
  #
  #     class MiceController < ApplicationController
  #       include Heimdallr::Resource
  #
  #       # Class Mouse must include Heimdallr::Model.
  #       resource_for :mouse
  #     end
  #
  # Resource is built with Convention over Configuration principle in mind; that is,
  # instead of providing complex configuration syntax, Resource consists of a lot of small, easy
  # to override methods. If some kind of default behavior is undesirable, then one can just override
  # the relative method in the particular controller or, say, define a module if the changes are
  # to be shared between several controllers. You are encouraged to explore the source of this class.
  #
  # Resource allows to perform efficient operations on collections of objects. The
  # {#create}, {#update} and {#destroy} actions accept both a single object/ID or an array of
  # objects/IDs. The cardinal _modus
  #
  # Resource only works with ActiveRecord.
  #
  # See also {Resource::ClassMethods}.
  module Resource
    def index
    end

    def show
    end

    def new
      render :json => {
        :fields => model.restrictions(security_context).whitelist[:create]
      }
    end

    def create
      model.transaction do
        if params.has_key? model.name.underscore
          scoped_model.new.to_proxy(security_context, :create).
            update_attributes!(params[model.name.underscore])
        else
          @resources.each_with_index do |resource, index|
            scoped_model.new.to_proxy(security_context, :create).
              update_attributes!(params[model.name.underscore.pluralize][index])
          end
        end
      end

      render_modified_resources
    end

    def edit
      render :json => {
        :fields => model.restrictions(security_context).whitelist[:update]
      }
    end

    def update
      model.transaction do
        if params.has_key? model.name.underscore
          @resources.first.to_proxy(security_context, :update).
            update_attributes!(params[model.name.underscore])
        else
          @resources.each_with_index do |resource, index|
            resource.to_proxy(security_context, :update).
            update_attributes!(params[model.name.underscore.pluralize][index])
          end
        end
      end

      render_modified_resources
    end

    def destroy
      model.transaction do
        @resources.each &:destroy
      end

      render :json => {}, :status => :ok
    end

    protected

    # Return the associated model class.
    # @return [Class] associated model
    def model
      self.class.model
    end

    # Return the appropriately scoped model. By default this method
    # delegates to +self.model.scoped+; you may override it for nested
    # resources so that it would only return the nested set.
    #
    # For example, this code would not allow user to perform any actions
    # with a transaction from a wrong account, raising RecordNotFound
    # instead:
    #
    #     # transactions_controller.rb
    #     class TransactionsController < ApplicationController
    #       include Heimdallr::Resource
    #
    #       resource_for :transactions
    #
    #       protected
    #
    #       def scoped_model
    #         Account.find(params[:account_id]).transactions
    #       end
    #     end
    #
    #     # routes.rb
    #     Foo::Application.routes.draw do
    #       resources :accounts do
    #         resources :transactions
    #       end
    #     end
    #
    # @return ActiveRecord scope
    def scoped_model
      self.model.scoped
    end

    # Loads all resources in the current scope to +@resources+.
    #
    # Is automatically applied to {#index}.
    def load_all_resources
      @resources = scoped_model
    end

    # Loads one resource from the current scope, referenced by <code>params[:id]</code>,
    # to +@resource+.
    #
    # Is automatically applied to {#show}.
    def load_one_resource
      @resource  = scoped_model.find(params[:id])
    end

    # Loads several resources from the current scope, referenced by <code>params[:id]</code>
    # with a comma-separated string like "1,2,3", to +@resources+.
    #
    # Is automatically applied to {#update} and {#destroy}.
    def load_referenced_resources
      @resources = scoped_model.find(params[:id].split(','))
    end

    # Renders a modified collection in {#create}, {#update} and similar actions.
    #
    # By default, invokes a template for +index+.
    def render_modified_resources
      render :action => :index
    end

    extend ActiveSupport::Concern

    module ClassMethods
      # Returns the attached model class.
      # @return [Class]
      attr_reader :model

      # Attaches this resource to a model.
      #
      # Note that ActiveSupport +before_filter+ _replaces_ the list of actions for specified
      # filter and not appends to it. For example, the following code will only run +filter_a+
      # when +bar+ action is invoked:
      #
      #     class FooController < ApplicationController
      #       before_filter :filter_a, :only => :foo
      #       before_filter :filter_a, :only => :bar
      #
      #       def foo; end
      #       def bar; end
      #     end
      #
      # For convenience, you can pass additional actions to register with default filters in
      # +options+. It is also possible to use +append_before_filter+.
      #
      # @param [Class] model An ActiveModel or ActiveRecord model class.
      # @option options [Array<Symbol>] :index
      #   Additional actions to be covered by {Heimdallr::Resource#load_all_resources}.
      # @option options [Array<Symbol>] :member
      #   Additional actions to be covered by {Heimdallr::Resource#load_one_resource}.
      # @option options [Array<Symbol>] :collection
      #   Additional actions to be covered by {Heimdallr::Resource#load_referenced_resources}.
      def resource_for(model, options={})
        @model = model.to_s.camelize.constantize

        before_filter :load_all_resources,          only: [ :index ].concat(options[:all] || [])
        before_filter :load_one_resource,           only: [ :show  ].concat(options[:member] || [])
        before_filter :load_referenced_resources,   only: [ :update, :destroy ].concat(options[:collection] || [])
      end
    end
  end
end