# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

require 'dialoghelper'
require 'pathname'
require 'viewtheme'
require 'fileutils'

class PreferenceDialog
  include DialogHelper
  attr_accessor :delegate
  attr_writer :window
  attr_writer :hotkey
  attr_writer :transcript_folder
  attr_writer :theme
  attr_writer :highlightArrayController, :dislikeArrayController, :ignoreArrayController
  attr_writer :highlightTable, :dislikeTable, :ignoreTable
  
  include Preferences::KVOCallbackHelper
  extend Preferences::AccessorHelpers
  
  defaults_string_array_kvc_accessor :highlight_words, 'preferences.keyword.words'
  defaults_string_array_kvc_accessor :dislike_words, 'preferences.keyword.dislike_words'
  defaults_string_array_kvc_accessor :ignore_words, 'preferences.keyword.ignore_words'

  # KVC accessors  
  attr_accessor :sounds
  attr_accessor :available_sounds
  attr_accessor :log_font
  attr_accessor :dcc_last_port
  attr_accessor :max_log_lines

  def init
    if super
      @available_sounds = preferences.sound.available_sounds
      @sounds = preferences.sound.events_wrapped
      @log_font = NSFont.fontWithName(preferences.theme.log_font_name, size:preferences.theme.log_font_size)
      @dcc_last_port = preferences.dcc.last_port
      @max_log_lines = preferences.general.max_log_lines
      @prefix = 'preferenceDialog'
      self
    end
  end
  
  def start
    NSBundle.loadNibNamed('PreferenceDialog', owner:self)
    
    load_theme
    update_transcript_folder
    
    preferences.theme.observe(:override_log_font, self)
    
    if preferences.general.use_hotkey?
      @hotkey.setKeyCode(preferences.general.hotkey_key_code, modifierFlags:preferences.general.hotkey_modifier_flags)
    else
      @hotkey.clearKey
    end
    @hotkey.delegate = self
    
    show
  end
  
  def show
    @window.center unless @window.isVisible
    @window.makeKeyAndOrderFront(self)
  end
  
  def close
    @delegate = nil
    @window.close
  end
  
  def windowWillClose(sender)
    NSFontPanel.sharedFontPanel.orderOut(nil)
    @log_dialog.cancel(nil) if @log_dialog
    fire_event('onClose')
  end
  
  def onLayoutChanged(sender)
    NSApp.delegate.update_layout
  end
  
  def hotkeyUpdated(hotkey)
    if @hotkey.valid?
      preferences.general.use_hotkey = true
      preferences.general.hotkey_key_code = @hotkey.keyCode
      preferences.general.hotkey_modifier_flags = @hotkey.modifierFlags
      NSApp.registerHotKey_modifierFlags(@hotkey.keyCode, @hotkey.modifierFlags)
    else
      preferences.general.use_hotkey = false
      NSApp.unregisterHotKey
    end
  end
  
  # Validate these values before setting them on the preferences.
  
  def dcc_last_port=(port)
    preferences.dcc.last_port = @dcc_last_port = port
  end
  
  def max_log_lines=(max)
    preferences.general.max_log_lines = @max_log_lines = max.to_i
  end
  
  def validateValue(value, forKeyPath:key, error:error)
    case key
    when 'dcc_last_port'
      value.assign(value[0].to_i < preferences.dcc.first_port.to_i ? preferences.dcc.first_port : value[0])
    when 'max_log_lines'
      value.assign(100) if value[0].to_i <= 100
    end
    true
  end
  
  # Highligh
  
  def editTable(table)
    row = table.numberOfRows - 1
    table.scrollRowToVisible(row)
    table.editColumn(0, row:row, withEvent:nil, select:true)
  end
  
  def editHighlightWord
    editTable(@highlightTable)
  end
  
  def editDislikeWord
    editTable(@dislikeTable)
  end
  
  def editIgnoreWord
    editTable(@ignoreTable)
  end
  
  def onAddHighlightWord(sender)
    @highlightArrayController.add(nil)
    performSelector('editHighlightWord', withObject:nil, afterDelay:0)
  end
  
  def onAddDislikeWord(sender)
    @dislikeArrayController.add(nil)
    performSelector('editDislikeWord', withObject:nil, afterDelay:0)
  end
  
  def onAddIgnoreWord(sender)
    @ignoreArrayController.add(nil)
    performSelector('editIgnoreWord', withObject:nil, afterDelay:0)
  end
  
  # Transcript
  
  def onTranscriptFolderChanged(sender)
    if @transcript_folder.selectedItem.tag == 2
      return if @log_dialog
      @log_dialog = NSOpenPanel.openPanel
      @log_dialog.setCanChooseFiles(false)
      @log_dialog.setCanChooseDirectories(true)
      @log_dialog.setResolvesAliases(true)
      @log_dialog.setAllowsMultipleSelection(false)
      @log_dialog.setCanCreateDirectories(true)
      path = Pathname.new(preferences.general.transcript_folder.expand_path)
      dir = path.parent
      @log_dialog.beginForDirectory(dir, file:nil, types:nil, modelessDelegate:self, didEndSelector:'transcriptFilePanelDidEnd:returnCode:contextInfo:', contextInfo:nil)
    end
  end
  
  def transcriptFilePanelDidEnd(panel, returnCode:code, contextInfo:info)
    @log_dialog = nil
    @transcript_folder.selectItem(@transcript_folder.itemAtIndex(0))
    return if code != NSOKButton
    path = panel.filenames[0]
    FileUtils.mkpath(path) rescue nil
    preferences.general.transcript_folder = path.collapse_path
    update_transcript_folder
  end
  
  def update_transcript_folder
    path = Pathname.new(preferences.general.transcript_folder).expand_path
    title = path.basename
    i = @transcript_folder.itemAtIndex(0)
    i.setTitle(title.to_s)
    icon = NSWorkspace.sharedWorkspace.iconForFile(path.to_s)
    icon.setSize(NSSize.new(16,16))
    i.setImage(icon)
  end
  
  # Log Font
  
  def onSelectFont(sender)
    fm = NSFontManager.sharedFontManager
    fm.setSelectedFont_isMultiple(@log_font, false)
    fm.orderFrontFontPanel(self)
  end
  
  def changeFont(sender)
    # use the kvc_accessor setter method, which send the appropriate KVO messages
    self.log_font = sender.convertFont(@log_font)
    preferences.theme.log_font_name = @log_font.fontName
    preferences.theme.log_font_size = @log_font.pointSize
    onLayoutChanged(nil)
  end
  
  # Called when preferences.theme.override_log_font is changed.
  def override_log_font_changed(override)
    onLayoutChanged(nil)
  end
  
  # Theme
  
  def onChangedTheme(sender)
    save_theme
    onLayoutChanged(nil)
  end
  
  def onOpenThemePath(sender)
    path = Pathname.new(ViewTheme.USER_BASE)
    unless path.exist?
      path.mkpath rescue nil
    end
    files = Dir.glob(path + '/*') rescue []
    if files.empty?
      # copy sample themes
      FileUtils.cp(Dir.glob(ViewTheme.RESOURCE_BASE + '/Sample.*'), ViewTheme.USER_BASE) rescue nil
    end
    NSWorkspace.sharedWorkspace.openFile(path)
  end
  
  private
  
  def load_theme
    @theme.removeAllItems
    @theme.addItemWithTitle('Default')
    @theme.itemAtIndex(0).setTag(0)
    
    [ViewTheme.RESOURCE_BASE, ViewTheme.USER_BASE].each_with_index do |base,tag|
      files = Pathname.glob(base + '/*.css') + Pathname.glob(base + '/*.yaml')
      files.map! {|i| i.basename('.*')}
      files.delete('Sample') if tag == 0
      files.uniq!
      files.sort_by {|i| i.to_s.downcase}
      unless files.empty?
        @theme.menu.addItem(NSMenuItem.separatorItem)
        count = @theme.numberOfItems
        files.each_with_index do |f,n|
          item = NSMenuItem.alloc.initWithTitle(f.to_s, action:nil, keyEquivalent:'')
          item.setTag(tag)
          @theme.menu.addItem(item)
        end
      end
    end
    
    kind, name = ViewTheme.extract_name(preferences.theme.name)
    target_tag = kind == 'resource' ? 0 : 1
    
    count = @theme.numberOfItems
    (0...count).each do |n|
      i = @theme.itemAtIndex(n)
      if i.tag == target_tag && i.title == name
        @theme.selectItemAtIndex(n)
        break
      end
    end
  end
  
  def save_theme
    sel = @theme.selectedItem
    fname = sel.title
    if sel.tag == 0
      preferences.theme.name = ViewTheme.resource_filename(fname)
    else
      preferences.theme.name = ViewTheme.user_filename(fname)
    end
  end
end
