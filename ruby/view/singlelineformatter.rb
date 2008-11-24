# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

require 'utility'

class SingleLineFormatter < NSFormatter
  
  def stringForObjectValue(str)
    str.to_s.gsub(/\r\n|\r|\n/, ' ')
  end
  
  def getObjectValue(objp, forString:str, errorDescription:err)
    s = str.to_s.gsub(/\r\n|\r|\n/, ' ')
    objp.assign(s)
    true
  end
  
  def isPartialStringValid(str, newEditingString:strp, errorDescription:err)
    return true unless str =~ /\r\n|\r|\n/
    s = str.gsub(/\r\n|\r|\n/, ' ')
    strp.assign(s)
    false
  end
end
