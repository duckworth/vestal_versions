[![Build Status](https://github.com/duckworth/vestal_versions/actions/workflows/test.yml/badge.svg)](https://github.com/duckworth/vestal_versions/actions/workflows/test.yml)
# Vestal Versions

Finally, DRY ActiveRecord versioning!

`acts_as_versioned[http://github.com/technoweenie/acts_as_versioned]` by
[technoweenie](http://github.com/technoweenie) was a great start, but it
failed to keep up with ActiveRecord's introduction of dirty objects in version
2.1. Additionally, each versioned model needs its own versions table that
duplicates most of the original table's columns. The versions table is then
populated with records that often duplicate most of the original record's
attributes. All in all, not very DRY.

`vestal_versions[http://github.com/laserlemon/vestal_versions]` requires only
one versions table (polymorphically associated with its parent models) and no
changes whatsoever to existing tables. But it goes one step DRYer by storing a
serialized hash of *only* the models' changes. Think modern version control
systems. By traversing the record of changes, the models can be reverted to
any point in time.

And that's just what `vestal_versions` does. Not only can a model be reverted
to a previous version number but also to a date or time!

## Changes in this fork

This fork adds the ability to find versions where a specific attribute
changed, useful for determining the previous value of a tracked attribute. The
2 new methods are `versions.find_with_attribute(attr)` and
`versions.find_last_with_attribute(attr)`. (See example below for usage.)

It also namespaces the versions table to "vestal_versions" and includes
compatability for Rails 4+ with ProtectedAttributes gem.

## Compatibility

Supports Active Record 7.0 through 8.1. Rails 8.0 and 8.1 require Ruby 3.2 or newer.
Configuration uses `ActiveSupport::InheritableOptions`, preserving the `config`
and `configure` APIs without Rails 8.1's `ActiveSupport::Configurable` deprecation.
Active Record 8.2 and newer remain excluded until compatibility is verified.

Run a compatibility suite by choosing `7_0`, `7_1`, `7_2`, `8_0`, or `8_1`:

    AR_VERSION=8_0
    BUNDLE_GEMFILE=gemfiles/activerecord_${AR_VERSION}.gemfile bundle install
    BUNDLE_GEMFILE=gemfiles/activerecord_${AR_VERSION}.gemfile bundle exec rspec

## Installation

In the Gemfile:

    gem 'vestal_versions', :git => 'git://github.com/neilgupta/vestal_versions'

Next, generate and run the first and last versioning migration you'll ever
need:

    $ rails generate vestal_versions:migration
    $ rake db:migrate

## Example

To version an ActiveRecord model, simply add `versioned` to your class like
so:

    class User < ActiveRecord::Base
      versioned

      validates_presence_of :first_name, :last_name

      def name
        "#{first_name} #{last_name}"
      end
    end

It's that easy! Now watch it in action...

    >> u = User.create(:first_name => "Steve", :last_name => "Richert")
    => #<User first_name: "Steve", last_name: "Richert">
    >> u.version
    => 1
    >> u.update_attribute(:first_name, "Stephen")
    => true
    >> u.name
    => "Stephen Richert"
    >> u.version
    => 2
    >> u.revert_to(10.seconds.ago)
    => 1
    >> u.name
    => "Steve Richert"
    >> u.version
    => 1
    >> u.save
    => true
    >> u.version
    => 3
    >> u.update_attribute(:last_name, "Jobs")
    => true
    >> u.name
    => "Steve Jobs"
    >> u.version
    => 4
    >> u.versions.find_with_attribute(:last_name)
    => [#<VestalVersions::Version id: 3, versioned_id: 4, versioned_type: "User", user_id: nil, user_type: nil, user_name: nil, modifications: {"last_name"=>["Richert", "Jobs"]}, number: 4, reverted_from: nil, tag: nil, created_at: "2014-10-16 02:55:40", updated_at: "2014-10-16 02:55:40">]
    >> u.revert_to!(2)
    => true
    >> u.name
    => "Stephen Richert"
    >> u.version
    => 5

## Upgrading to 1.0

For the most part, version 1.0 of `vestal_versions` is backwards compatible,
with just a few notable changes:

*   The versions table has been beefed up. You'll need to add the following
    columns (and indexes, if you feel so inclined):

        change_table :versions do |t|
          t.belongs_to :user, :polymorphic => true
          t.string :user_name
          t.string :tag
        end

        change_table :versions do |t|
          t.index [:user_id, :user_type]
          t.index :user_name
          t.index :tag
        end

*   When a model is created (or updated the first time after being versioned),
    an initial version record with a number of 1 is no longer created. These
    aren't used during reversion and so they end up just being dead weight.
    Feel free to scrap all your versions where `number == 1` after the upgrade
    if you'd like to free up some room in your database (but you don't have
    to).

*   Models that have no version records in the database will return a
    `@user.version` of 1. In the past, this would have returned `nil` instead.

*   `Version` has moved to `VestalVersions::Version` to make way for custom
    version classes.

*   `Version#version` did not survive the move to
    `VestalVersions::Version#version`. That alias was dropped (too confusing).
    Use `VestalVersions::Version#number`.


## New to 1.0

There are a handful of exciting new additions in version 1.0 of
`vestal_versions`. A lot has changed in the code: much better documentation,
more modular organization of features, and a more exhaustive test suite. But
there are also a number of new features that are available in this release of
`vestal_versions`:

*   The ability to completely skip versioning within a new `skip_version`
    block:

        @user.version # => 1
        @user.skip_version do
          @user.update_attribute(:first_name, "Stephen")
          @user.first_name = "Steve"
          @user.save
          @user.update(:last_name => "Jobs")
        end
        @user.version # => 1

    Also available, are `merge_version` and `append_version` blocks. The
    `merge_version` block will compile the possibly multiple versions that
    would result from the updates inside the block into one summary version.
    The single resulting version is then tacked onto the version history as
    usual. The `append_version` block works similarly except that the
    resulting single version is combined with the most recent version in the
    history and saved.

*   Version tagging. Any version can have a tag attached to it (must be unique
    within the scope of the versioned parent) and that tag can be used for
    reversion.

        @user.name # => "Steve Richert"
        @user.update_attribute(:last_name, "Jobs")
        @user.name # => "Steve Jobs"
        @user.tag_version("apple")
        @user.update_attribute(:last_name, "Richert")
        @user.name # => "Steve Richert"
        @user.revert_to("apple")
        @user.name # => "Steve Jobs"

    So if you're not big on version numbers, you could just tag your versions
    and avoid the numbers altogether.

*   Resetting. This is basically a hard revert. The new `reset_to!` instance
    method behaves just like the `revert_to!` method except that after the
    reversion, it will also scrap all the versions that came after that target
    version.

        @user.name # => "Steve Richert"
        @user.version # => 1
        @user.versions.count # => 0
        @user.update_attribute(:last_name, "Jobs")
        @user.name # => "Steve Jobs"
        @user.version # => 2
        @user.versions.count # => 1
        @user.reset_to!(1)
        @user.name # => "Steve Richert"
        @user.version # => 1
        @user.versions.count # => 0

*   Storing which user is responsible for a revision. Rather than introduce a
    lot of controller magic to guess what to store, you can simply update an
    additional attribute on your versioned model: `updated_by`.

        @user.update(:last_name => "Jobs", :updated_by => "Tyler")
        @user.versions.last.user # => "Tyler"

    Instead of passing a simple string to the `updated_by` setter, you can
    pass a model instance, such as an ActiveRecord user or administrator. The
    association will be saved polymorphically alongside the version.

        @user.update(:last_name => "Jobs", :updated_by => current_user)
        @user.versions.last.user # => #<User first_name: "Steven", last_name: "Tyler">

*   Global configuration. The new `vestal_versions` Rails generator also
    writes an initializer with instructions on how to set application-wide
    options for the `versioned` method.

*   Conditional version creation. The `versioned` method now accepts `:if` and
    `:unless` options. Each expects a symbol representing an instance method
    or a proc that will be evaluated to determine whether or not to create a
    new version after an update. An array containing any combination of
    symbols and procs can also be given.

        class User < ActiveRecord::Base
          versioned :if => :really_create_a_version?
        end

*   Custom version classes. By passing a `:class_name` option to the
    `versioned` method, you can specify your own ActiveRecord version model.
    `VestalVersions::Version` is the default, but feel free to stray from
    that. I recommend that your custom model inherit from
    `VestalVersions::Version`, but that's up to you!

*   A `versioned?` convenience class method. If your user model is versioned,
    `User.versioned?` will let you know.

*   Soft Deletes & Restoration.  By setting `:dependent` to `:tracking`
    destroys will be tracked.  On destroy a new version will be created
    storing the complete details of the object with a tag of 'deleted'.  The
    object can later be restored using the `restore!` method on the
    VestalVersions::Version record.  The attributes of the restored object
    will be set using the attribute writer methods.  After a restore! is
    performed the version record with the 'deleted' tag is removed from the
    history.

        class User < ActiveRecord::Base
          versioned :dependent => :tracking
        end

        >> @user.version
        => 2
        >> @user.destroy
        => <User id: 2, first_name: "Steve", last_name: "Jobs", ... >
        >> User.find(2)
        => ActiveRecord::RecordNotFound: Couldn't find User with ID=2
        >> VestalVersions::Version.last
        => <VestalVersions::Version id: 4, versioned_id: 2, versioned_type: "User", user_id: nil, user_type: nil, user_name: nil, modifications: {"created_at"=>Sun Aug 01 18:39:57 UTC 2010, "updated_at"=>Sun Aug 01 18:42:28 UTC 2010, "id"=>2, "last_name"=>"Jobs", "first_name"=>"Stephen"}, number: 3, tag: "deleted", created_at: "2010-08-01 18:42:43", updated_at: "2010-08-01 18:42:43">
        >> VestalVersions::Version.last.restore!
        => <User id: 2, first_name => "Steven", last_name: "Jobs", ... >
        >> @user = User.find(2)
        => <User id: 2, first_name => "Steven", last_name: "Jobs", ... >
        >> @user.version
        => 2


