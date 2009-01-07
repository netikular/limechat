module NSUserDefaultsExtension
  def [](key)
    valueForKey(key)
  end
  
  def []=(key, value)
    setValue(value, forKey: key)
  end
  
  def delete(key)
    removeObjectForKey(key)
  end
end

NSUserDefaults.send(:include, NSUserDefaultsExtension)
