# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

require 'utility'

class SingleLineFormatter < NSFormatter
  
  def stringForObjectValue(str)
    str.to_s.gsub(/\r\n|\r|\n/, ' ')
  end
  
  def getObjectValue(objp, forString:str, errorDescription:err)
    s = str.to_s.gsub(/\r\n|\r|\n/, ' ')
    objp.assign(s.to_ns)
    true
  end
  
  def isPartialStringValid(str, newEditingString:strp, errorDescription:err)
    s = str.to_s
    return true unless s =~ /\r\n|\r|\n/
    s = s.gsub(/\r\n|\r|\n/, ' ')
    strp.assign(s.to_ns)
    false
  end
end
