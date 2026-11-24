; On-screen display used to show the active layout name (see LAYOUT_SWITCH_* options)

InitOSD() {
  global osd, osdText, osdX, osdY

  taskbarHeight := 0
  try WinGetPos(, , , &taskbarHeight, "ahk_class Shell_TrayWnd")

  osdX := LAYOUT_SWITCH_X_OFFSET
  osdY := A_ScreenHeight - taskbarHeight + 8 + LAYOUT_SWITCH_Y_OFFSET

  ; osd := Gui("+AlwaysOnTop -Caption +ToolWindow")
  osd := Gui("-Caption +ToolWindow")
  osd.BackColor := "000000"
  osd.SetFont("s10 cWhite w700 q3", "Verdana")

  WinSetExStyle("+0x20", osd) ; Make the GUI window click-through
  WinSetTransColor("000000 215", osd)

  osdText := osd.AddText("Center w" A_ScreenWidth " h18", "0")
}

ShowMessage(message, color := "White", timer := false) {
  if (not message) {
    osd.Hide()
    return
  }

  osdText.Value := message
  osdText.SetFont("c" color)
  try osd.Show("X" osdX " Y" osdY " NA")

  SetTimer(HideOSD, 0)
  if (timer)
    SetTimer(HideOSD, -timer)
}

HideOSD() {
  osd.Hide()
}
