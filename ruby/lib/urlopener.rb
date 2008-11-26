# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

module UrlOpener
  
  def openUrl(str)
    urls = [NSURL.URLWithString(str)]
    NSWorkspace.sharedWorkspace.openURLs(urls, withAppBundleIdentifier:nil, options:NSWorkspaceLaunchAsync, additionalEventParamDescriptor:nil, launchIdentifiers:nil)
  end
  
  extend self
end
