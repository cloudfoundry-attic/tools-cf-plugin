[![Build Status](https://travis-ci.org/cloudfoundry/tools-cf-plugin.png)](https://travis-ci.org/cloudfoundry/tools-cf-plugin)
[![Gem Version](https://badge.fury.io/rb/tools-cf-plugin.png)](http://badge.fury.io/rb/tools-cf-plugin)

## Tools
### Info

This plugin provides various utility commands for administering/monitoring a Cloud Foundry deployment.

### Installation

If you have installed CF via gem install, use:
```
gem install tools-cf-plugin
```

If you have installed CF through bundler and the Gemfile, add the following to your Gemfile:
```
gem "tools-cf-plugin"
```

### Usage

```
watch APP       Watch messages going over NATS relevant to an application
```