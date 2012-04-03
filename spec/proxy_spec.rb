require 'spec_helper'

class User
  attr_accessor :admin

  def initialize(admin)
    @admin = admin
  end

  def admin?
    @admin
  end
end

class Entity < ActiveRecord::Base
  include Heimdallr::Model

  belongs_to :owner, :class_name => 'User'

  restrict do |user|
    if user.admin? || user == self.owner
      # Administrator or owner can do everything
      scope :fetch
      scope :destroy
      can [:view, :create, :update]
    else
      # Other users can view only non-classified articles...
      scope :fetch, -> { where('secrecy_level < ?', 5) }

      # ... and see all fields except the actual security level...
      can    :view
      cannot :view, [:secrecy_level]

      # ... and can create them with certain restrictions.
      can :create, %w(content)
      can [:create, :update], {
        owner:         user,
        secrecy_level: { inclusion: { in: 0..4 } }
      }
    end
  end
end

describe Heimdallr::Proxy do
  before(:each) do
    @admin  = User.new(true)
    @looser = User.new(false)
  end

  it "should apply restrictions" do
    proxy = Entity.restrict(@admin)
  end
end