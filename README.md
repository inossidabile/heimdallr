Heimdallr
=========

Heimdallr is a gem for managing security restrictions for ActiveRecord objects on field level; think
of it as a supercharged [CanCan](https://github.com/ryanb/cancan). Heimdallr favors whitelisting over blacklisting,
convention over configuration and is duck-type compatible with most of existing code.

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
        can    :view
      else
        can    :view
        cannot :view, [:secrecy_level]
      end

      # ... and can create them with certain restrictions.
      can :create, %w(content)
      can [:create, :update], {
        owner:         user,
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
secure.create! content: "My second article"
# => Article(id: 4, owner: johndoe, content: "My second article", security_level: 0)

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

Typical cases
-------------

While working with MVC you'll mostly use Heimdallr-wrapped models inside your controllers and views. To
protect your controllers using DSL from the model you can use [Heimdallr::Resource](http://github.com/roundlake/heimdallr-resource) extension gem.

To facilitate views you can use `implicit` strategy which is described above.

Compatibility
-------------

Ruby 1.8 and ActiveRecord versions prior to 3.0 are not supported.

Licensing
---------

    Copyright (C) 2012  Peter Zotov <whitequark@whitequark.org>

    Funded by Round Lake.

    Permission is hereby granted, free of charge, to any person obtaining a copy of
    this software and associated documentation files (the "Software"), to deal in
    the Software without restriction, including without limitation the rights to
    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
    of the Software, and to permit persons to whom the Software is furnished to do
    so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.