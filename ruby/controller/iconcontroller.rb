# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

class IconController
  def initialize
    @highlight = @newTalk = false
  end
  
  def update(highlight, newTalk, textChange = false)
    return if highlight == @highlight && newTalk == @newTalk && textChange == @textChange
    @highlight = highlight
    @newTalk = newTalk
    @textChange = textChange
    icon =  NSImage.imageNamed(:NSApplicationIcon)
    puts textChange
    if highlight || newTalk || textChange
      icon = icon.copy
      begin
        icon.lockFocus
        if highlight
          @highlightBadge ||= NSImage.imageNamed(:redstar)
          draw_badge(@highlightBadge, icon.size)
        elsif newTalk
          @newTalkBadge ||= NSImage.imageNamed(:bluestar)
          draw_badge(@newTalkBadge, icon.size)
        elsif textChange
          puts textChange
          @textChangeBadge ||= NSImage.imageNamed(:yellowstar)
          draw_badge(@textChangeBadge, icon.size)
        end
      ensure
        icon.unlockFocus
      end
    end
    NSApp.setApplicationIconImage(icon)
  end
  
  private
  
  def draw_badge(badge, icon_size)
    size = badge.size
    w = size.width
    h = size.height
    x = icon_size.width - w
    y = icon_size.height - h
    badge.compositeToPoint_operation(NSPoint.new(x, y), NSCompositeSourceOver)
  end
  
end
