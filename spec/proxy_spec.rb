require 'spec_helper'

class User < ActiveRecord::Base; end

class Article < ActiveRecord::Base
  include Heimdallr::Model

  belongs_to :owner, :class_name => 'User'

  restrict do |user|
    if user.admin? #|| user == self.owner
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
  before(:all) do
    @john = User.create! :admin => false
    Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 10
  end

  before(:each) do
    @admin  = User.new :admin => true
    @looser = User.new :admin => false
  end

  it "should apply restrictions" do
    proxy = Article.restrict(@admin)
    proxy.should be_a_kind_of Heimdallr::Proxy::Collection

    proxy = Article.restrict(@looser)
    proxy.should be_a_kind_of Heimdallr::Proxy::Collection
  end

  it "should handle fetch scope" do
    Article.restrict(@john).all.count.should == 1
    Article.restrict(@admin).all.count.should == 1
    Article.restrict(@looser).all.count.should == 0
  end
end