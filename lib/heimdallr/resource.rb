module Heimdallr
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

      if block_given?
        yield
      else
        render_modified_resources
      end
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

      if block_given?
        yield
      else
        render_modified_resources
      end
    end

    def destroy
      model.transaction do
        @resources.each &:destroy
      end

      render :json => {}, :status => :ok
    end

    protected

    def model
      self.class.model
    end

    def scoped_model
      self.model.scoped
    end

    def load_all_resources
      @resources = scoped_model
    end

    def load_one_resource
      @resource  = scoped_model.find(params[:id])
    end

    def load_referenced_resources
      @resources = scoped_model.find(params[:id].split(','))
    end

    def render_modified_resources
      render :action => :index
    end

    extend ActiveSupport::Concern

    module ClassMethods
      attr_reader :model

      def resource_for(model, options={})
        @model = model.to_s.camelize.constantize

        before_filter :load_all_resources,          only: [ :index ].concat(options[:all] || [])
        before_filter :load_one_resource,           only: [ :show  ].concat(options[:member] || [])
        before_filter :load_referenced_resources,   only: [ :update, :destroy ].concat(options[:collection] || [])
      end
    end
  end
end