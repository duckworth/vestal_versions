require 'spec_helper'
require 'open3'

describe 'VestalVersions configuration' do
  it 'configures global options through the public API' do
    result = VestalVersions.configure do |config|
      expect(config).to equal(VestalVersions.config)
      config.initial_version = true
      :configured
    end

    expect(result).to eq(:configured)
    expect(VestalVersions.config[:initial_version]).to eq(true)
    User.prepare_versioned_options({})
    expect(User.vestal_versions_options[:initial_version]).to eq(true)
  end

  it 'inherits settings applied after a subclass configuration is accessed' do
    subclass = Class.new(VestalVersions::Version)
    config = subclass.config
    VestalVersions.config.initial_version = true

    expect(config.initial_version).to eq(true)
    VestalVersions.config.initial_version = false
    expect(config.initial_version).to eq(false)
  end

  it 'keeps subclass overrides separate from parent and sibling settings' do
    subclass = Class.new(VestalVersions::Version)
    sibling = Class.new(VestalVersions::Version)
    VestalVersions.config.initial_version = true
    subclass.configure { |config| config.initial_version = false }

    expect(subclass.config.initial_version).to eq(false)
    expect(VestalVersions.config.initial_version).to eq(true)
    expect(sibling.config.initial_version).to eq(true)
    expect(Class.new(subclass).config.initial_version).to eq(false)
  end

  it 'restores inherited settings when subclass overrides are cleared' do
    subclass = Class.new(VestalVersions::Version)
    VestalVersions.config.initial_version = true
    subclass.config.initial_version = false
    subclass.config.clear

    expect(subclass.config.initial_version).to eq(true)
  end

  it 'keeps instance overrides separate from class and other instance settings' do
    version = VestalVersions::Version.new
    config = version.config
    VestalVersions.config.initial_version = true
    expect(config.initial_version).to eq(true)

    config.initial_version = false
    expect(version.config.initial_version).to eq(false)
    expect(VestalVersions.config.initial_version).to eq(true)
    expect(VestalVersions::Version.new.config.initial_version).to eq(true)
  end

  it 'uses global configuration for initial versions with a custom version model' do
    VestalVersions.configure do |config|
      config.class_name = 'MyCustomVersion'
      config.initial_version = true
    end
    stub_const('ConfiguredUser', Class.new(ActiveRecord::Base))
    ConfiguredUser.table_name = 'users'
    ConfiguredUser.versioned

    user = ConfiguredUser.create!(:first_name => 'Steve')
    expect(user.versions.first).to be_a(MyCustomVersion)
    expect(user.versions.first.number).to eq(1)
    user.update!(:first_name => 'Stephen')
    expect(user.versions.last.reload.modifications['first_name']).to eq(['Steve', 'Stephen'])
  end

  it 'loads configuration when Active Support deprecations raise' do
    script = <<~RUBY
      require 'active_record'
      deprecator = ActiveSupport.respond_to?(:deprecator) ? ActiveSupport.deprecator : ActiveSupport::Deprecation
      deprecator.behavior = :raise
      require 'vestal_versions'
      VestalVersions.configure { |config| config.initial_version = true }
    RUBY
    lib = File.expand_path('../../lib', __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib, '-e', script)

    expect(status.success?).to eq(true), "#{stdout}\n#{stderr}"
  end
end
