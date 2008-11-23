class TextFieldWithDisabledState < NSTextField
  def setEnabled(enabled)
    super(enabled)
    setTextColor(enabled == 1 ? NSColor.controlTextColor : NSColor.disabledControlTextColor)
  end
end