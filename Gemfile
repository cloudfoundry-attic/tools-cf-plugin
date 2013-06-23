source "http://rubygems.org"

gem "cfoundry", :github => "cloudfoundry/cfoundry", :submodules => true, :tag => "v1.5.3"
gem "cf", :github => "cloudfoundry/cf", :ref => "3cde1f1f6d"

git "git://github.com/cloudfoundry/bosh.git" do
  gem "bosh_cli"
  gem "bosh_common"
  gem "blobstore_client"
end

gemspec
