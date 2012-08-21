def run_specs(user_model, article_model, dont_save_model)
  before(:all) do
    user_model.destroy_all
    article_model.destroy_all
    dont_save_model.destroy_all

    @john = user_model.create! :admin => false
    @banned = user_model.create! :banned => true
    article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 10
    article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 3
  end

  before(:each) do
    @admin  = user_model.new :admin => true
    @looser = user_model.new :admin => false
  end

  it "should apply restrictions" do
    proxy = article_model.restrict(@admin)
    proxy.should be_a_kind_of Heimdallr::Proxy::Collection

    proxy = article_model.restrict(@looser)
    proxy.should be_a_kind_of Heimdallr::Proxy::Collection
  end

  it "should handle fetch scope" do
    article_model.restrict(@admin).all.count.should == 2
    article_model.restrict(@looser).all.count.should == 1
    article_model.restrict(@john).all.count.should == 2
  end

  it "should handle destroy scope" do
    article = article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@looser).destroy }.to raise_error
    expect { article.restrict(@john).destroy }.to_not raise_error

    article = article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@admin).destroy }.to_not raise_error
  end

  it "should handle list of fields to view" do
    article = article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 0
    expect { article.restrict(@looser).secrecy_level }.to raise_error
    expect { article.restrict(@admin).secrecy_level }.to_not raise_error
    expect { article.restrict(@john).secrecy_level }.to_not raise_error
    article.restrict(@looser).id.should == article.id
    article.restrict(@looser).content.should == 'test'
  end

  it "should handle entities creation" do
    expect { article_model.restrict(@looser).create! :content => 'test', :secrecy_level => 10 }.to raise_error

    article = article_model.restrict(@john).create! :content => 'test', :secrecy_level => 3
    article.owner_id.should == @john.id
  end

  it "should handle entities update" do
    article = article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 10
    expect {
      article.restrict(@john).update_attributes! :secrecy_level => 8
    }.to raise_error
    expect {
      article.restrict(@looser).update_attributes! :secrecy_level => 3
    }.to raise_error
    expect {
      article.restrict(@admin).update_attributes! :secrecy_level => 10
    }.to_not raise_error
  end

  it "should handle implicit strategy" do
    article = article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 4
    expect { article.restrict(@looser).secrecy_level }.to raise_error
    article.restrict(@looser).implicit.secrecy_level.should == nil
  end

  it "should answer if object is creatable" do
    article_model.restrict(@john).should be_creatable
    article_model.restrict(@admin).should be_creatable
    article_model.restrict(@looser).should be_creatable
  end

  it "should answer if object is modifiable" do
    article = article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 4
    article.restrict(@john).should be_modifiable
    article.restrict(@admin).should be_modifiable
    article.restrict(@looser).should_not be_modifiable
  end

  it "should answer if object is destroyable" do
    article = article_model.create! :owner_id => @john.id, :content => 'test', :secrecy_level => 4
    article.restrict(@john).should be_destroyable
    article.restrict(@admin).should be_destroyable
    article.restrict(@looser).should_not be_destroyable
  end

  it "should not create anything else if it did not saved" do
    expect {
      article_model.restrict(@looser).create! :content => 'test', :secrecy_level => 10, :dont_save => 'ok' rescue nil
    }.not_to change(dont_save_model, :count)
  end

  context "when user has no rights to view" do
    it "should not be visible" do
      article = article_model.create! :content => 'test', :owner => @john, :secrecy_level => 0
      article.restrict(@banned).should_not be_visible
    end
  end

  context "when user has no rights to create" do
    it "should not be creatable" do
      article_model.restrict(@banned).should_not be_creatable
      expect {
        article_model.restrict(@banned).create! :content => 'test', :secrecy_level => 0
      }.to raise_error
    end
  end
end

