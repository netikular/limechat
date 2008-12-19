# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

class Resolver
  def self.resolve(sender, host)
    Thread.new do
      addr = Resolv.getaddresses(host)
      sender.performSelectorOnMainThread('ResolverOnResolve:', withObject:addr, waitUntilDone:false)
    end
    nil
  end
end
