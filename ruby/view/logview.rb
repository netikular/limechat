# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

class LogView < WebView
  attr_accessor :key_delegate, :resize_delegate
  
  def keyDown(e)
    @key_delegate.logView_keyDown(e) if @key_delegate
  end
  
  def setFrame(rect)
    @resize_delegate.logView_willResize(rect) if @resize_delegate
    super(rect)
    @resize_delegate.logView_didResize(rect) if @resize_delegate
  end
  
  #objc_method :maintainsInactiveSelection, 'c@:'
  def maintainsInactiveSelection
    true
  end
  
  def clearSel
    setSelectedDOMRange_affinity(nil, NSSelectionAffinityDownstream)
  end
  
  def selection
    sel = selectedDOMRange.cloneContents
    return nil unless sel
    iter = selectedFrame.DOMDocument.createNodeIterator_whatToShow_filter_expandEntityReferences(sel, DOM_SHOW_TEXT, nil, true)
    s = ''
    while node = iter.nextNode
      s << node.nodeValue
    end
    s.empty? ? nil : s
  end
end
