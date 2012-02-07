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
  # Resource expects a method named +security_context+ to be defined either in the controller itself
  # or, more conveniently, in any of its ancestors, likely +ApplicationController+. This method can
  # often be aliased to +current_user+.
  #
  # Resource only works with ActiveRecord.
  #
  # See also {Resource::ClassMethods}.
  module Resource
    # @group Actions

    # +GET /resources+
    #
    # This action does nothing by itself, but it has a +load_all_resources+ filter attached.
    def index
    end

    # +GET /resource/1+
    #
    # This action does nothing by itself, but it has a +load_one_resource+ filter attached.
    def show
    end

    # +GET /resources/new+
    #
    # This action renders a JSON representation of fields whitelisted for creation.
    # It does not include any fixtures or validations.
    #
    # @example
    #   { 'fields': [ 'topic', 'content' ] }
    def new
      render :json => {
        :fields => model.restrictions(security_context).allowed_fields[:create]
      }
    end

    # +POST /resources+
    #
    # This action creates one or more records from the passed parameters.
    # It can accept both arrays of attribute hashes and single attribute hashes.
    #
    # After the creation, it calls {#render_resources}.
    #
    # See also {#load_referenced_resources} and {#with_objects_from_params}.
    def create
      with_objects_from_params do |attributes, index|
        scoped_model.restrict(security_context).
            create!(attributes)
      end

      render_resources
    end

    # +GET /resources/1/edit+
    #
    # This action renders a JSON representation of fields whitelisted for updating.
    # See also {#new}.
    def edit
      render :json => {
        :fields => model.restrictions(security_context).allowed_fields[:update]
      }
    end

    # +PUT /resources/1,2+
    #
    # This action updates one or more records from the passed parameters.
    # It expects resource IDs to be passed comma-separated in <tt>params[:id]</tt>,
    # and expects them to be in the order corresponding to the order of actual
    # attribute hashes.
    #
    # After the updating, it calls {#render_resources}.
    #
    # See also {#load_referenced_resources} and {#with_objects_from_params}.
    def update
      with_objects_from_params do |attributes, index|
        @resources[index].update_attributes! attributes
      end

      render_resources
    end

    # +DELETE /resources/1,2+
    #
    # This action destroys one or more records. It expects resource IDs to be passed
    # comma-separated in <tt>params[:id]</tt>.
    #
    # See also {#load_referenced_resources}.
    def destroy
      model.transaction do
        @resources.each &:destroy
      end

      render :json => {}, :status => :ok
    end

    protected

    # @group Configuration

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

    # Render a modified collection in {#create}, {#update} and similar actions.
    #
    # By default, it invokes a template for +index+.
    def render_resources
      render :action => :index
    end

    # Fetch one or several objects passed in +params+ and yield them to a block,
    # wrapping everything in a transaction.
    #
    # @yield [attributes, index]
    # @yieldparam [Hash] attributes
    # @yieldparam [Integer] index
    def with_objects_from_params
      model.transaction do
        if params.has_key? model.name.underscore
          yield params[model.name.underscore], 0
        else
          params[model.name.underscore.pluralize].
                each_with_index do |attributes, index|
            yield attributes, index
          end
        end
      end
    end

    extend ActiveSupport::Concern

    # Class methods for {Heimdallr::Resource}. See also +ActiveSupport::Concern+.
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
      # @param [Class] model an +ActiveRecord+-derived model class
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