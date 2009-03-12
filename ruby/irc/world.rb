# Created by Satoshi Nakagawa.
# You can redistribute it and/or modify it under the Ruby's license or the GPL2.

require 'date'

class IRCWorld < NSObject
  attr_accessor :member_list, :dcc, :view_theme, :window
  attr_writer :app, :tree, :log_base, :console_base, :chat_box, :field_editor, :text
  attr_accessor :menu_controller
  attr_accessor :tree_default_menu, :server_menu, :channel_menu, :tree_menu, :log_menu, :console_menu, :url_menu, :addr_menu, :chan_menu, :member_menu
  attr_reader :units, :selected, :prev_selected, :console, :config

  AUTO_CONNECT_DELAY = 1
  RECONNECT_AFTER_WAKE_UP_DELAY = 5

  def initialize
    @units = []
    @unit_id = 0
    @channel_id = 0
    @growl = GrowlController.new
    @icon = IconController.new
    @growl.owner = self
    @today = Date.today
  end

  def setup(seed)
    @console = create_log(nil, nil, true)
    @console_base.setContentView(@console.view)
    @dummylog = create_log(nil, nil, true)
    @log_base.setContentView(@dummylog.view)

    @config = seed.dup
    @config.units.each {|u| create_unit(u) } if @config.units
    @config.units = nil

    change_input_text_theme
    change_member_list_theme
    change_tree_theme
    register_growl

    #@plugin = PluginManager.new(self, '~/Library/LimeChat/Plugins')
    #@plugin.load_all
  end

  def save
    preferences.save_world(to_dic)
  end

  def setup_tree
    @tree.setTarget(self)
    @tree.setDoubleAction('outlineView_doubleClicked:')
  	@tree.registerForDraggedTypes(TREE_DRAG_ITEM_TYPES);

    unit = @units.find {|u| u.config.auto_connect }
    if unit
      expand_unit(unit)
      unless unit.channels.empty?
        @tree.select(@tree.rowForItem(unit)+1)
      else
        @tree.select(@tree.rowForItem(unit))
      end
    elsif @units.size > 0
      select(@units[0])
    end
    outlineViewSelectionDidChange(nil)
  end

  def terminate
    @units.each {|u| u.terminate }
  end

  def update_order(w)
    ary = []
    w.units.each do |i|
      u = find_unit_by_id(i.uid)
      if u
        u.update_order(i)
        ary << u
        @units.delete(u)
      end
    end
    ary += @units
    @units = ary
    reload_tree
    adjust_selection
    save
  end

  def update_autoop(w)
    @config.autoop = w.autoop
    w.units.each do |i|
      u = find_unit_by_id(i.uid)
      u.update_autoop(i) if u
    end
    save
  end

  def store_tree
    w = @config.dup
    w.units = @units.map {|u| u.store_config }
    w
  end

  def auto_connect(after_wake_up=false)
    delay = 0
    delay += RECONNECT_AFTER_WAKE_UP_DELAY if after_wake_up
    @units.each do |u|
      if (!after_wake_up) && u.config.auto_connect || after_wake_up && u.reconnect
        u.auto_connect(delay)
        delay += AUTO_CONNECT_DELAY
      end
    end
  end

  def prepare_for_sleep
    @units.each {|u| u.disconnect(true) }
  end

  def selunit
    return nil unless @selected
    @selected.unit? ? @selected : @selected.unit
  end

  def selchannel
    return nil unless @selected
    @selected.unit? ? nil : @selected
  end

  def sel
    [selunit, selchannel]
  end

  def to_dic
    h = @config.to_dic
    unless @units.empty?
      h[:units] = @units.map {|i| i.to_dic }
    end
    h
  end

  def find_unit(name)
    @units.find {|u| u.name == name }
  end

  def find_unit_by_id(uid)
    @units.find {|u| u.uid == uid }
  end

  def find_channel_by_id(uid, cid)
    unit = @units.find {|u| u.uid == uid }
    return nil unless unit
    unit.channels.find {|c| c.uid == cid }
  end

  def find_by_id(uid, cid)
    unit = find_unit_by_id(uid)
    return [] unless unit
    channel = unit.find_channel_by_id(cid)
    [unit, channel]
  end

  def create_unit(seed, reload=true)
    @unit_id += 1
    u = IRCUnit.alloc.init
    u.uid = @unit_id
    u.world = self
    u.log = create_log(u)
    u.setup(seed)
    seed.channels.each {|c| create_channel(u, c) } if seed.channels
    @units << u
    reload_tree if reload
    u
  end

  def destroy_unit(unit)
    unit.terminate
    unit.disconnect
    if @selected && @selected.unit == unit
      select_other_and_destroy(unit)
    else
      @units.delete(unit)
      reload_tree
      adjust_selection
    end
  end

  def create_channel(unit, seed, reload=true, adjust=true)
    c = unit.find_channel(seed.name)
    return c if c

    @channel_id += 1
    c = IRCChannel.alloc.init
    c.uid = @channel_id
    c.unit = unit
    c.setup(seed)
    c.log = create_log(unit, c)

    case seed.type
    when :channel
      n = unit.channels.index {|i| i.talk? }
      if n
        unit.channels.insert(n, c)
      else
        unit.channels << c
      end
    when :talk
      n = unit.channels.index {|i| i.dccchat? }
      if n
        unit.channels.insert(n, c)
      else
        unit.channels << c
      end
    when :dccchat
      unit.channels << c
    end

    reload_tree if reload
    adjust_selection if adjust
    expand_unit(unit) if unit.login? && unit.channels.size == 1
    c
  end

  def create_talk(unit, nick)
    c = create_channel(unit, IRCChannelConfig.new({:name => nick, :type => :talk}))
    if unit.login?
      c.activate
      c.add_member(User.new(unit.mynick))
      c.add_member(User.new(nick))
    end
    c
  end

  def destroy_channel(channel)
    channel.terminate
    unit = channel.unit
    case channel.type
    when :channel
      unit.part_channel(channel) if unit.login? && channel.active?
    when :talk
    when :dccchat
    end
    if unit.last_selected_channel == channel
      unit.last_selected_channel = nil
    end
    if @selected == channel
      select_other_and_destroy(channel)
    else
      unit.channels.delete(channel)
      reload_tree
      adjust_selection
    end
  end

  def adjust_selection
    row = @tree.selectedRow
    if row >= 0 && @selected && @selected != @tree.itemAtRow(row)
      @tree.select(@tree.rowForItem(@selected))
      reload_tree
    end
  end

  def clear_text
    @text.setStringValue('')
  end

  def input_text(s, cmd)
    return false unless @selected
    @selected.unit.input_text(s, cmd)
  end

  def select_text
    @text.focus
  end

  def store_prev_selected
    if !@selected
      @prev_selected = nil
    elsif @selected.unit?
      @prev_selected = [@selected.uid, nil]
    else
      @prev_selected = [@selected.unit.uid, @selected.uid]
    end
  end

  def select_prev
    return unless @prev_selected
    uid, cid = @prev_selected
    if cid
      i = find_channel_by_id(uid, cid)
    else
      i = find_unit_by_id(uid)
    end
    select(i) if i
  end

  def select(item)
    store_prev_selected
    select_text
    unless item
      @selected = nil
      @log_base.setContentView(@dummylog.view)
      @member_list.setDataSource(nil)
      @member_list.reloadData
      @tree.setMenu(@tree_menu)
      return
    end
    @tree.expandItem(item.unit) unless item.unit?
    i = @tree.rowForItem(item)
    return if i < 0
    @tree.select(i)
    item.unit.last_selected_channel = item.unit? ? nil : item
  end

  def select_channel_at(n)
    return unless @selected
    unit = @selected.unit
    return select(unit) if n == 0
    n -= 1
    channel = unit.channels[n]
    select(channel) if channel
  end

  def select_unit_at(n)
    unit = @units[n]
    return unless unit
    t = unit.last_selected_channel
    t = unit unless t
    select(t)
  end

  def expand_unit(unit)
    @tree.expandItem(unit)
  end

  def update_unit_title(unit)
    return unless unit && @selected
    update_title if @selected.unit == unit
  end

  def update_channel_title(channel)
    return unless channel
    update_title if @selected == channel
  end

  def update_title
    if @selected
      sel = @selected
      if sel.unit?
        u = sel
        nick = u.mynick
        mymode = u.mymode.to_s
        name = u.config.name
        title =
          if nick.empty?
            "#{name}"
          elsif mymode.empty?
            "(#{nick}) #{name}"
          else
            "(#{nick}) (#{mymode}) #{name}"
          end
        @window.setTitle(title)
      else
        u = sel.unit
        c = sel
        nick = u.mynick
        chname = c.name
        count = c.count_members
        mode = c.mode.masked_str
        topic = c.topic
        if topic =~ /\A(.{25})/
          topic = $1 + '...'
        end
        title =
          if c.channel?
            op = if c.op?
              m = c.find_member(u.mynick)
              if m && m.op?
                m.mark
              else
                ''
              end
            else
              ''
            end

            if mode.empty?
              if count <= 1
                "(#{nick}) #{op}#{chname} #{topic}"
              else
                "(#{nick}) #{op}#{chname} (#{count}) #{topic}"
              end
            else
              if count <= 1
                "(#{nick}) #{op}#{chname} (#{mode}) #{topic}"
              else
                "(#{nick}) #{op}#{chname} (#{count},#{mode}) #{topic}"
              end
            end
          else
            "(#{nick}) #{chname}"
          end
        @window.setTitle(title)
      end
    end
  end

  def reload_tree
    if @reloading_tree
      @tree.setNeedsDisplay(true)
      return
    end
    @reloading_tree = true
    @tree.reloadData
    @reloading_tree = false
  end

  def register_growl
    @growl.register if preferences.general.use_growl
  end

  def notify_on_growl(kind, title, desc, context=nil)
    if preferences.general.use_growl
      register_growl
      return if preferences.general.stop_growl_on_active && NSApp.isActive
      @growl.notify(kind, title, desc, context)
    end
  end

  def update_icon
    highlight = newtalk = textchange = false

    @units.each do |u|
      if u.keyword
        highlight = true
        break
      end

      u.channels.each do |c|
        if c.keyword
          highlight = true
          break
        end
        if c.newtalk
          newtalk = true
        end   
        textchange = true if c.unread
      end
    end

    @icon.update(highlight, newtalk, textchange)
  end

  def reload_theme
    @view_theme.theme = preferences.theme.name

    logs = [@console]

    @units.each do |u|
      logs << u.log
      u.channels.each do |c|
        logs << c.log
      end
    end

    logs.each do |log|
      if preferences.theme.override_log_font
        log.override_font = [preferences.theme.log_font_name, preferences.theme.log_font_size]
      else
        log.override_font = nil
      end
      log.reload_theme
    end

    change_input_text_theme
    change_tree_theme
    change_member_list_theme

    #sel = selected
    #@log_base.setContentView(sel.log.view) if sel
    #@console_base.setContentView(@console.view)
  end

  def change_input_text_theme
    theme = @view_theme.other
    @field_editor.setInsertionPointColor(theme.input_text_color)
    @text.setTextColor(theme.input_text_color)
    @text.setBackgroundColor(theme.input_text_bgcolor)
    @chat_box.set_input_text_font(theme.input_text_font)
  end

  def change_tree_theme
    theme = @view_theme.other
    @tree.setFont(theme.tree_font)
    @tree.theme_changed
    @tree.setNeedsDisplay(true)
  end

  def change_member_list_theme
    theme = @view_theme.other
    @member_list.setFont(theme.member_list_font)
    @member_list.tableColumns[0].dataCell.theme_changed
    @member_list.theme_changed
    @member_list.setNeedsDisplay(true)
  end

  def preferences_changed
    @console.max_lines = preferences.general.max_log_lines
    @units.each {|u| u.preferences_changed}
    reload_theme
  end

  def date_changed
    @units.each {|u| u.date_changed}
  end

  def change_text_size(op)
    logs = [@console]
    @units.each do |u|
      logs << u.log
      u.channels.each do |c|
        logs << c.log
      end
    end
    logs.each {|i| i.change_text_size(op)}
  end

  def reload_plugins
    #@plugin.load_all
  end

  def mark_all_as_read
    @units.each do |u|
      u.unread = false
      u.channels.each do |c|
        c.unread = false
      end
    end
    reload_tree
  end

  def mark_all_scrollbacks
    @units.each do |u|
      u.log.mark
      u.channels.each do |c|
        c.log.mark
      end
    end
  end

  # delegate

  def outlineView_doubleClicked(sender)
    return unless @selected
    u, c = sel
    unless c
      if u.connecting? || u.connected? || u.login?
        u.quit if preferences.general.disconnect_on_doubleclick
      else
        u.connect if preferences.general.connect_on_doubleclick
      end
    else
      if u.login?
        if c.active?
          u.part_channel(c) if preferences.general.leave_on_doubleclick
        else
          u.join_channel(c) if preferences.general.join_on_doubleclick
        end
      end
    end
  end

  def outlineView_shouldEditTableColumn_item(sender, column, item)
    false
  end

  def outlineViewSelectionIsChanging(note)
    store_prev_selected
    outlineViewSelectionDidChange(note)
  end

  def outlineViewSelectionDidChange(note)
    selitem = @tree.itemAtRow(@tree.selectedRow)
    if @selected != selitem
      @selected.last_input_text = @text.stringValue.to_s if @selected
      @app.addToHistory
      if selitem
        @text.setStringValue(selitem.last_input_text || '')
      else
        @text.setStringValue('')
      end
      select_text
    end
    unless selitem
      @log_base.setContentView(@dummylog.view)
      @tree.setMenu(@tree_menu)
      @member_list.setDataSource(nil)
      @member_list.setDelegate(nil)
      @member_list.reloadData
      return
    end
    selitem.reset_state
    @selected = selitem
    @log_base.setContentView(selitem.log.view)
    if selitem.unit?
      @tree.setMenu(@server_menu.submenu)
      @member_list.setDataSource(nil)
      @member_list.setDelegate(nil)
      @member_list.reloadData
      selitem.last_selected_channel = nil
    else
      @tree.setMenu(@channel_menu.submenu)
      @member_list.setDataSource(selitem)
      @member_list.setDelegate(selitem)
      @member_list.reloadData
      selitem.unit.last_selected_channel = selitem
    end
    @member_list.deselectAll(self)
    @member_list.scrollRowToVisible(0)
    @selected.log.view.clearSel
    update_title
    reload_tree
    update_icon
  end

  def outlineViewItemDidCollapse(notification)
    item = notification.userInfo.objectForKey('NSObject')
    select(item) if item
  end

  # data source

  def outlineView_numberOfChildrenOfItem(sender, item)
    return @units.size unless item
    item.number_of_children
  end

  def outlineView_isItemExpandable(sender, item)
    item.number_of_children > 0
  end

  def outlineView_child_ofItem(sender, index, item)
    return @units[index] unless item
    item.child_at(index)
  end

  def outlineView_objectValueForTableColumn_byItem(sender, column, item)
    item.label
  end

  # tree

  def serverTreeView_acceptFirstResponder
    select_text
  end

  def outlineView_willDisplayCell_forTableColumn_item(sender, cell, col, item)
    theme = @view_theme.other

    if item.keyword
      textcolor = theme.tree_highlight_color
    elsif item.newtalk
      textcolor = theme.tree_newtalk_color
    elsif item.unread
      textcolor = theme.tree_unread_color
    elsif item.unit? ? item.login? : item.active?
      if item == @tree.itemAtRow(@tree.selectedRow) && NSApp.isActive
        textcolor = theme.tree_sel_active_color
      else
        textcolor = theme.tree_active_color
      end
    else
      if item == @tree.itemAtRow(@tree.selectedRow)
        textcolor = theme.tree_sel_inactive_color
      else
        textcolor = theme.tree_inactive_color
      end
    end
    cell.setTextColor(textcolor)
  end

  # tree drag and drop

  TREE_DRAG_ITEM_TYPE = 'treeitem'
  TREE_DRAG_ITEM_TYPES = [TREE_DRAG_ITEM_TYPE]

  def outlineView_writeItems_toPasteboard(sender, items, pboard)
    i = items.to_a[0]
    if i.is_a?(IRCUnit)
      s = "#{i.uid}"
    else
      s = "#{i.unit.uid}-#{i.uid}"
    end
    pboard.declareTypes_owner(TREE_DRAG_ITEM_TYPES, self)
    pboard.setPropertyList_forType(s, TREE_DRAG_ITEM_TYPE)
    true
  end

  def find_item_from_pboard(s)
    if /^(\d+)-(\d+)$/ =~ s
      u = $1.to_i
      c = $2.to_i
      find_channel_by_id(u, c)
    elsif /^\d+$/ =~ s
      find_unit_by_id(s.to_i)
    else
      nil
    end
  end

  def outlineView_validateDrop_proposedItem_proposedChildIndex(sender, info, item, index)
    return NSDragOperationNone if index < 0
  	pboard = info.draggingPasteboard
  	return NSDragOperationNone unless pboard.availableTypeFromArray(TREE_DRAG_ITEM_TYPES)
    target = pboard.propertyListForType(TREE_DRAG_ITEM_TYPE)
    return NSDragOperationNone unless target
    i = find_item_from_pboard(target.to_s)
    return NSDragOperationNone unless i

    if i.is_a?(IRCUnit)
      return NSDragOperationNone if item
    else
      return NSDragOperationNone unless item
      return NSDragOperationNone if item != i.unit
      if i.talk?
        ary = item.channels
        low = ary[0...index] || []
        high = ary[index...ary.size] || []
        low.delete(i)
        high.delete(i)
        next_item = high[0]

        # don't allow talks dropped above channels
        return NSDragOperationNone if next_item && next_item.channel?
      end
    end
    NSDragOperationGeneric
  end

  def outlineView_acceptDrop_item_childIndex(sender, info, item, index)
    return false if index < 0
  	pboard = info.draggingPasteboard
  	return false unless pboard.availableTypeFromArray(TREE_DRAG_ITEM_TYPES)
    target = pboard.propertyListForType(TREE_DRAG_ITEM_TYPE)
    return false unless target
    i = find_item_from_pboard(target.to_s)
    return false unless i

    if i.is_a?(IRCUnit)
      return false if item

      ary = @units
      low = ary[0...index] || []
      high = ary[index...ary.size] || []
      low.delete(i)
      high.delete(i)
      @units.replace(low + [i] + high)
      reload_tree
      save
    else
      return false unless item
      return false if item != i.unit

      ary = item.channels
      low = ary[0...index] || []
      high = ary[index...ary.size] || []
      low.delete(i)
      high.delete(i)
      item.channels.replace(low + [i] + high)
      reload_tree
      save if i.channel?
    end
    adjust_selection
    true
  end

  # log view

  def log_doubleClick(s)
    ary = s.split(' ')
    case ary[0]
    when 'unit'
      uid = ary[1].to_i
      unit = find_unit_by_id(uid)
      select(unit) if unit
    when 'channel'
      uid = ary[1].to_i
      cid = ary[2].to_i
      channel = find_channel_by_id(uid, cid)
      select(channel) if channel
    end
  end

  def log_keyDown(e)
    @window.makeFirstResponder(@text)
    select_text
    case e.keyCode.to_i
    when 36,76  # enter / num_enter
      ;
    else
      @window.sendEvent(e)
    end
  end

  # list view

  def memberListView_keyDown(e)
    @window.makeFirstResponder(@text)
    select_text
    case e.keyCode.to_i
    when 36,76  # enter / num_enter
      ;
    else
      @window.sendEvent(e)
    end
  end

  def memberListView_dropFiles(files, row)
    u, c = sel
    return unless u && c
    m = c.members[row]
    if m
      files.each {|f| @dcc.add_sender(u.uid, m.nick, f, false) }
    end
  end

  # timer

  def on_timer
    @units.each {|u| u.on_timer }
    @dcc.on_timer

    date = Date.today
    if @today != date
      @today = date
      date_changed
    end
  end

  private

  def select_other_and_destroy(target)
    if target.unit?
      i = @units.index(target)
      sel = @units[i+1]
      i = @tree.rowForItem(target)
    else
      i = @tree.rowForItem(target)
      sel = @tree.itemAtRow(i+1)
      if sel && sel.unit?
        # we don't want to change units when closing a channel
        sel = @tree.itemAtRow(i-1)
      end
    end
    if sel
      select(sel)
    else
      sel = @tree.itemAtRow(i-1)
      if sel
        select(sel)
      else
        select(nil)
      end
    end
    if target.unit?
      target.channels.each {|c| c.close_dialogs }
      @units.delete(target)
    else
      target.unit.channels.delete(target)
    end
    reload_tree
    if @selected
      i = @tree.rowForItem(sel)
      @tree.select(i, true)
    end
  end

  def create_log(unit, channel=nil, console=false)
    log = LogController.alloc.init
    log.menu = console ? @console_menu : @log_menu
    log.url_menu = @url_menu
    log.addr_menu = @addr_menu
    log.chan_menu = @chan_menu
    log.member_menu = @member_menu
    log.world = self
    log.unit = unit
    log.channel = channel
    log.keyword = preferences.keyword
    log.max_lines = preferences.general.max_log_lines
    log.theme = @view_theme
    if preferences.theme.override_log_font
      log.override_font = [preferences.theme.log_font_name, preferences.theme.log_font_size]
    else
      log.override_font = nil
    end
    log.setup(console, @view_theme.other.input_text_bgcolor)
    log.view.setHostWindow(@window)
    log.view.setTextSizeMultiplier(@console.view.textSizeMultiplier) if @console
    log
  end

end
