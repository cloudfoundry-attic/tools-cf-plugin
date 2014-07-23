[![Build Status](https://travis-ci.org/cloudfoundry/tools-cf-plugin.png)](https://travis-ci.org/cloudfoundry/tools-cf-plugin)[![Gem Version](https://badge.fury.io/rb/tools-cf-plugin.png)](http://badge.fury.io/rb/tools-cf-plugin)

Tools
-----

### Info

This plugin provides various utility commands for administering/monitoring a Cloud Foundry deployment.

### Conflicts

To use this plugin, during installation bundler will install the legacy `cf` CLI which will be added into your `$PATH`.

The Requirements & Installation sections below includes a solution. The constraint is that you must install the tool and its dependencies into an RVM gemset to isolate it from the rest of the environment, and run the tool from within the project folder.

### Requirements

This plugin, and the legacy `cf` CLI, require Ruby 1.9.3 (not Ruby 2.0+).

```
rvm install 1.9.3
```

### Installation

Bundler is the most reliable way to run cf tools:

```bash
git clone https://github.com/cloudfoundry/tools-cf-plugin
cd tools-cf-plugin/

rvm 1.9.3@tools-cf-plugin --create --ruby-version

bundle
ssh-add <bosh_ssh_keys>/<your id_rsa for director> # use your key for the director or microbosh
ssh vcap@<your bosh director> id # check connectivity
bundle exec cf tunnel-nats <your bosh director> dea-apps --gateway vcap@<your bosh director>
```

### Usage if you have direct access to the NATS server

```bash
bundle exec cf watch <APP>       # Watch messages going over NATS relevant to an application
bundle exec cf dea-apps        # See summary information about apps running on DEAs
bundle exec cf dea-ads         # Watch the DEA advertisements
bundle exec cf app-placement   # See the distribution of apps over DEAs
```

### Usage if you must tunnel to the NATS server

```bash
bundle exec cf tunnel-nats <your bosh director> watch <APP> --gateway vcap@<your bosh director>
bundle exec cf tunnel-nats <your bosh director> dea-apps --gateway vcap@<your bosh director>
bundle exec cf tunnel-nats <your bosh director> dea-ads --gateway vcap@<your bosh director>
bundle exec cf tunnel-nats <your bosh director> app-placement --gateway vcap@<your bosh director>
```
