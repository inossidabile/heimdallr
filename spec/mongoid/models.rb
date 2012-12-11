require 'mongoid'
require 'orm_adapter/adapters/mongoid'

ENV['RACK_ENV'] ||= 'test'
Mongoid.load!('tmp/mongoid.yml')

class Mongoid::User
  include Mongoid::Document
  field :admin, type: Boolean
  field :banned, type: Boolean
  field :dude_id, type: String
  include Heimdallr::Model
  has_one :buddy, :class_name => self.name, :foreign_key => :dude_id
  belongs_to :dude, :class_name => self.name
  restrict do |user|
    scope :fetch
  end
end

class Mongoid::DontSave
  include Mongoid::Document
  field :name
end

class Mongoid::Article
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content
  field :secrecy_level, type: Fixnum

  belongs_to :owner, class_name: 'Mongoid::User'

  include Heimdallr::Model

  def self.by_id(id)
    where(:id => id)
  end

  def dont_save=(name)
    # Just don't do this in Mongo!
    # Mongoid::DontSave.create(:name => name)
  end

  restrict do |user, record|
    if user.banned?
      # banned users cannot do anything
      scope :fetch, proc { where('1' => 0) }
    elsif user.admin?
      # Administrator or owner can do everything
      scope :fetch
      scope :delete
      can [:view, :create, :update]
    else
      # Other users can view only their own or non-classified articles...
      scope :fetch,  -> { scoped.or({owner_id: user.id}, {:secrecy_level.lt => 5}) }
      scope :delete, -> { where(owner_id: user.id) }

      # ... and see all fields except the actual security level
      # (through owners can see everything)...
      if record.try(:owner) == user
        can :view
        can :update, {
          secrecy_level: { inclusion: { in: 0..4 } }
        }
      else
        can    :view
        cannot :view, [:secrecy_level]
      end

      # ... and can create them with certain restrictions.
      can :create, %w(content _type)
      can :create, {
        owner_id:      user.id,
        secrecy_level: { inclusion: { in: 0..4 } }
      }
    end
  end
end

class Mongoid::SubArticle < Mongoid::Article; end
