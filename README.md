WARNING
=======

**Heimdallr is still supported but is not under development anymore. Please check out its successor – the [Protector](http://github.com/inossidabile/protector).**

Also you might want to read [the article describing the reasons](http://staal.io/blog/2013/06/04/the-protector/) for this fork and actual changes.

Heimdallr
=========

Heimdallr is a gem for managing security restrictions for ActiveRecord objects on field level; think
of it as a supercharged [CanCan](https://github.com/ryanb/cancan). Heimdallr favors whitelisting over blacklisting,
convention over configuration and is duck-type compatible with most of existing code.

[![Travis CI](https://secure.travis-ci.org/roundlake/heimdallr.png)](https://travis-ci.org/inossidabile/heimdallr)
[![Code Climate](https://codeclimate.com/github/inossidabile/heimdallr.png)](https://codeclimate.com/github/inossidabile/heimdallr)

``` ruby
# Define a typical set of models.
class User < ActiveRecord::Base
  has_many :articles
end

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
          # each field may have validators that will allow update
          secrecy_level: { inclusion: { in: 0..4 } }
        }
      else
        can    :view
        cannot :view, [:secrecy_level]
      end

      # ... and can create them with certain restrictions.
      can :create, %w(content)
      can :create, {
        # each field may have fixed value that cannot be overridden
        owner_id:      user.id,
        secrecy_level: { inclusion: { in: 0..4 } }
      }
    end
  end
end

# Create some fictional data.
admin   = User.create admin: true
johndoe = User.create admin: false

Article.create id: 1, owner: admin,   content: "Nothing happens",  secrecy_level: 0
Article.create id: 2, owner: admin,   content: "This is a secret", secrecy_level: 10
Article.create id: 3, owner: johndoe, content: "Hello World"

# Get a restricted scope for the user.
secure = Article.restrict(johndoe)

# Use any ARel methods:
secure.pluck(:content)
# => ["Nothing happens", "Hello World"]

# Everything should be permitted explicitly:
secure.first.delete
# ! Heimdallr::PermissionError is raised
secure.find(1).secrecy_level
# ! Heimdallr::PermissionError is raised

# There is a helper for views to be easily written:
view_passed = secure.first.implicit
view_passed.secrecy_level
# => nil

# If only a single value is possible, it is inferred automatically:
secure.create! content: "My second article", secrecy_level: 0
# => Article(id: 4, owner: johndoe, content: "My second article", secrecy_level: 0)

# ... and cannot be changed:
secure.create! owner: admin, content: "I'm a haxx0r"
# ! Heimdallr::PermissionError is raised

# You can use any valid ActiveRecord validators, too:
secure.create! content: "Top Secret", secrecy_level: 10
# ! ActiveRecord::RecordInvalid is raised

# John Doe would not see what he is not permitted to, ever:
# -- I know that you have this classified material! It's in folder #2.
secure.find 2
# ! ActiveRecord::RecordNotFound is raised
# -- No, it is not.
```

The DSL is described in documentation for [Heimdallr::Model](http://rubydoc.info/gems/heimdallr/master/Heimdallr/Model).

Ideology
--------

Heimdallr aims to make security explicit, but nevertheless convenient. It does not allow one to call any
implicit operations which may be used maliciously; instead, it forces you to explicitly call `#insecure`
method which returns the underlying object. This single point of entry is easily recognizable with code.

Heimdallr has two restrictions strategies: explicit and implicit. By default it will use explicit strategy
that means it will raise an exception for every insecure request. Calling `.implicit` will give you a copy
of proxy object switched to another strategy. With that it will silently return nil for every attribute
that is inaccessible.

There are several options which alter Heimdallr's behavior in security-sensitive ways. They are described
in [Heimdallr](http://rubydoc.info/gems/heimdallr/master/Heimdallr).

Rails notes
-----------

As of Rails 3.2.3 attr_accessible is in whitelist mode by default. That makes no sense when using Heimdallr. To
turn it off set the `config.active_record.whitelist_attributes` value to false at yours `application.rb`.

Also you can not use restricted record with form helpers, but you can call `.insecure` method to get original model,
like this: `form_for(@user.insecure) do |f|`. Form helpers don't assign values anyway.

Mongoid notes
-------------

Heimdallr now has support for Mongoid. But please note that MongoDB doesn't support transactions,
so please be sure that all your assignments
are [atomic](http://docs.mongodb.org/manual/faq/developers/#how-do-i-do-transactions-and-locking-in-mongodb)
to prevent unexpected behaviour.

Depending on the way you include the Mongoid gem you might sometimes meet the following error: `undefined method 'to_adapter'`. It happens when you don't require Mongoid from your bundler but do it manually on the latter stages. In such cases you need to explicitly require the following file after Mongoid was included:

```ruby
require 'orm_adapter/adapters/mongoid'
```

Typical cases
-------------

While working with MVC you'll mostly use Heimdallr-wrapped models inside your controllers and views. To
protect your controllers using DSL from the model you can use [Heimdallr::Resource](http://github.com/roundlake/heimdallr-resource) extension gem.

To facilitate views you can use `implicit` strategy which is described above.

Compatibility
-------------

Ruby 1.8 and ActiveRecord versions prior to 3.0 are not supported.

I have a nice shiny pull request...
-----------------------------------

... and it involves delegating `is_a?`, `class`, `respond_to?` or a similar core method? Congratulations, you just broke one of the core assumptions others have of Ruby object. Heimdallr proxies are _duck-type_ compatible with the records; this does not, in any way, make them of the same Ruby type.

Consider the pull request already rejected.

Maintainers
-------

* Peter Zotov, [@whitequark](http://twitter.com/whitequark)
* Boris Staal, [@inossidabile](http://staal.io)

License
-------

It is free software, and may be redistributed under the terms of MIT license.
