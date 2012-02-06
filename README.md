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

  restrict do |user|
    if user.admin? || user == self.owner
      # Administrator or owner can do everything
      can :fetch
      can [:view, :create, :update, :destroy]
    else
      # Other users can view only non-classified articles...
      can :fetch, -> { where('secrecy_level < ?', 5) }

      # ... and see all fields except the actual security level...
      can    :view
      cannot :view, [:secrecy_level]

      # ... and can create them with certain restrictions.
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
secure.find(1).secrecy_level
# => nil

# Everything should be permitted explicitly:
secure.first.delete
# ! Heimdallr::PermissionError is raised

# If only a single value is possible, it is inferred automatically:
secure.create! content: "My second article"
# => Article(id: 4, owner: johndoe, content: "My second article", security_level: 0)

# ... and cannot be changed:
secure.create! owner: admin, content: "I'm a haxx0r"
# ! ActiveRecord::RecordInvalid is raised

# You can use any valid ActiveRecord validators, too:
secure.create! content: "Top Secret", secrecy_level: 10
# ! ActiveRecord::RecordInvalid is raised

# John Doe would not see what he is not permitted to, ever:
# -- I know that you have this classified material! It's in folder #2.
secure.find 2
# ! ActiveRecord::RecordNotFound is raised
# -- No, it is not.
```

The DSL is described in documentation for [Heimdallr::Model](http://rubydoc.info/gems/heimdallr/0.0.1/Heimdallr/Model).

Note that Heimdallr is designed with three goals in mind, in the following order:

 * Preventing malicious modifications
 * Preventing information leaks
 * Being convenient to use

Due to the last one, not all methods will raise an exception on invalid access; some will silently drop the offending
attribute or simply return `nil`. This is clearly described in the documentation, done intentionally and isn't
going to change.

REST interface
--------------

Heimdallr also favors REST pattern; while its use is not mandated, a Heimdallr::Resource module is provided, which
implements all standard REST actions with the extension of allowing to pass multiple models at once, and also enables
one to introspect all writable fields with `new` and `edit` actions.

The interface is described in documentation for [Heimdallr::Resource](http://rubydoc.info/gems/heimdallr/0.0.1/Heimdallr/Resource).

Compatibility
-------------

Ruby 1.8 and ActiveRecord versions prior to 3.0 are not supported.

Licensing
---------

    Copyright (C) 2012  Peter Zotov <whitequark@whitequark.org>

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