require 'spec_helper'

class User < ActiveRecord::Base; end

class Article < ActiveRecord::Base
  include Heimdallr::Model

  belongs_to :owner, :class_name => 'User'

  restrict do |user, record|
    if user.admin?
      # Administrator or owner can do everything
      scope :fetch
      scope :delete
      can [:view, :create, :update]
    else
      # Other users can view only their own or non-classified articles...
      scope :fetch,  -> { where('owner_id = ? or secrecy_level < ?', user.id, 5) }
      scope :delete, -> { where('owner_id = ?', user.id) }

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
      can :create, %w(content)
      can :create, {
        owner_id:      user.id,
        secrecy_level: { inclusion: { in: 0..4 } }
      }
    end
  end
end

describe Heimdallr::Proxy do
  before(:all) do
    @john = User.create! :admin => false
    Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 10
    Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 3
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
    Article.restrict(@admin).all.count.should == 2
    Article.restrict(@looser).all.count.should == 1
    Article.restrict(@john).all.count.should == 2
  end

  it "should handle destroy scope" do
    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@looser).destroy }.should raise_error
    expect { article.restrict(@john).destroy }.should_not raise_error

    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@admin).destroy }.should_not raise_error
  end

  it "should handle list of fields to view" do
    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@looser).secrecy_level }.should raise_error
    expect { article.restrict(@admin).secrecy_level }.should_not raise_error
    expect { article.restrict(@john).secrecy_level }.should_not raise_error
    article.restrict(@looser).content.should == 'test'
  end

  it "should handle entities creation" do
    expect { Article.restrict(@looser).create! :content => 'test', :secrecy_level => 10 }.should raise_error

    article = Article.restrict(@john).create! :content => 'test', :secrecy_level => 3
    article.owner_id.should == @john.id
  end

  it "should handle entities update" do
    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 10
    expect {
      article.restrict(@john).update_attributes! :secrecy_level => 8
    }.should raise_error
    expect {
      article.restrict(@looser).update_attributes! :secrecy_level => 3
    }.should raise_error
    expect {
      article.restrict(@admin).update_attributes! :secrecy_level => 10
    }.should_not raise_error
  end

  it "should handle implicit strategy" do
    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 4
    expect { article.restrict(@looser).secrecy_level }.should raise_error
    article.restrict(@looser).implicit.secrecy_level.should == nil
  end

  it "should answer if object is creatable" do
    Article.restrict(@john).creatable?.should == true
    Article.restrict(@admin).creatable?.should == true
    Article.restrict(@looser).creatable?.should == true
  end

  it "should answer if object is modifiable" do
    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 4
    article.restrict(@john).modifiable?.should == true
    article.restrict(@admin).modifiable?.should == true
    article.restrict(@looser).modifiable?.should == false
  end

  it "should answer if object is destroyable" do
    article = Article.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 4
    article.restrict(@john).destroyable?.should == true
    article.restrict(@admin).destroyable?.should == true
    article.restrict(@looser).destroyable?.should == false
  end
end