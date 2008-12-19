# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

require 'socket'

class Resolver
  def self.resolve(sender, host)
    Thread.new do
      addr = Socket.getaddrinfo(host, nil)
      sender.performSelectorOnMainThread('ResolverOnResolve:', withObject:addr, waitUntilDone:false)
    end
    nil
  end
end
