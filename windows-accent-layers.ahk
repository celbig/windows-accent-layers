#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
Persistent()
A_MaxHotkeysPerInterval := 300
ProcessSetPriority("High")
SetKeyDelay(-1)
FileEncoding("UTF-8") ; Keymaps without a BOM are read as UTF-8 (UTF-16 LE / UTF-8 BOM are auto-detected)

;@Ahk2Exe-SetMainIcon icon.ico
;@Ahk2Exe-Obey U_Version, = FileRead("%A_ScriptDir%\version")
;@Ahk2Exe-SetFileVersion %U_Version%
;@Ahk2Exe-SetProductVersion Build v%U_Version% AutoHotkey v%A_AhkVersion%

enabled := true
secondaryLayout := false

A_IconTip := "Windows Accent Layers"

OPTIONS_PATH := A_ScriptDir "\options.ini"

; Read options.ini (every key needs a default: v2 throws on missing keys)
ReadOption(name, default) => IniRead(OPTIONS_PATH, "Options", name, default)

HIDE_TRAY_ICON       := ReadOption("HIDE_TRAY_ICON", 0)
TIMEOUT              := ReadOption("TIMEOUT", 0.8)
ACTIVE_KEYMAP        := ReadOption("ACTIVE_KEYMAP", "macOS/macOS.txt")
IGNORE_WHEN_ACTIVE   := ReadOption("IGNORE_WHEN_ACTIVE", "")
NEOMOUSEKEYS_SUPPORT := ReadOption("NEOMOUSEKEYS_SUPPORT", 0)
PREFIX_CANCEL_MODE   := Integer(ReadOption("PREFIX_CANCEL_MODE", 0))
PREFIX_TIMEOUT       := ReadOption("PREFIX_TIMEOUT", 0.3) * 1000

LAYOUT_SWITCH_HOTKEY      := ReadOption("LAYOUT_SWITCH_HOTKEY", 0)
LAYOUT_SWITCH_SHOW_OSD    := ReadOption("LAYOUT_SWITCH_SHOW_OSD", 0)
LAYOUT_SWITCH_OSD_TIMEOUT := ReadOption("LAYOUT_SWITCH_OSD_TIMEOUT", 0)
LAYOUT_SWITCH_X_OFFSET    := ReadOption("LAYOUT_SWITCH_X_OFFSET", 0)
LAYOUT_SWITCH_Y_OFFSET    := ReadOption("LAYOUT_SWITCH_Y_OFFSET", 0)
LAYOUT_1_NAME             := ReadOption("LAYOUT_1_NAME", "")
LAYOUT_2_NAME             := ReadOption("LAYOUT_2_NAME", "")

InitOSD()

if (HIDE_TRAY_ICON)
  A_IconHidden := true
else if (!A_IsCompiled)
  try TraySetIcon(A_ScriptDir "\icon.ico", , true) ; v2 throws if the icon is missing

; Read ignored apps and add it to the ignore group
hasIgnoreGroup := false
if (IGNORE_WHEN_ACTIVE != "") {
  for element in StrSplit(IGNORE_WHEN_ACTIVE, ",", " ") {
    GroupAdd("AccentLayersIgnore", "ahk_exe " element)
    hasIgnoreGroup := true
  }
}

; Hotkeys/hotstrings that fail to register are reported once at startup
registrationErrors := []

TryHotkey(keyName, callback) {
  try
    Hotkey(keyName, callback)
  catch as e
    registrationErrors.Push("Hotkey  " keyName "  →  " e.Message)
}

TryHotstring(trigger, replacement) {
  try
    Hotstring(trigger, replacement)
  catch as e
    registrationErrors.Push("Hotstring  " trigger "  →  " e.Message)
}

; Layout switching
if (LAYOUT_SWITCH_HOTKEY) {
  ; Register symmetric if activation is modifier-only
  if (InStr(LAYOUT_SWITCH_HOTKEY, " & ")) {
    split := StrSplit(LAYOUT_SWITCH_HOTKEY, " & ")
    TryHotkey(split[2] " & " split[1], SwitchLayout)
  }

  TryHotkey(LAYOUT_SWITCH_HOTKEY, SwitchLayout)
  UpdateLayoutOSD()
}

; Read [ACTIVE_KEYMAP]
keyMap := Map("LAYER", Map(), "MAP", Map(), "TIMEOUT", Map(), "SPACE", Map(), "PREFIX", Map())
pressTime := Map()
KEYMAP_PATH := A_ScriptDir "\keymaps\" ACTIVE_KEYMAP

if (!FileExist(KEYMAP_PATH)) {
  MsgBox("Keymap not found:`n" KEYMAP_PATH "`n`nCheck ACTIVE_KEYMAP in options.ini.", "Windows Accent Layers", "Icon!")
  ExitApp()
}

IsEnabled() {
  return (enabled and not secondaryLayout
    and not (hasIgnoreGroup and WinActive("ahk_group AccentLayersIgnore")))
}

IsLayoutEnabled() {
  return (secondaryLayout = true)
}

HotIf((*) => IsEnabled())
Loop Read KEYMAP_PATH
{
  ; Comment line. Not a regex: AHK v2's PCRE throws on some valid characters (e.g. U+FB01 ﬁ, U+F8FF)
  if (SubStr(LTrim(A_LoopReadLine, " `t"), 1, 1) == ";")
    continue

  split := StrSplit(A_LoopReadLine, "=>", " ", 2)

  if (split.Length != 2)
    continue

  prefixSplit := StrSplit(split[1], " ", " ", 2)
  if (prefixSplit.Length != 2)
    continue

  cmd := prefixSplit[1]
  key := prefixSplit[2]

  data := cmd == "PREFIXMAP" ? split[2] : StrReplace(split[2], " ", "")

  if (!keyMap.Has(cmd))
    keyMap[cmd] := Map()
  keyMap[cmd][key] := data

  if (cmd == "LAYER") {
    TryHotkey(key, CallAccentLayers)
  } else if (cmd == "MAP") {
    TryHotkey(key, CallMap)
  } else if (cmd == "PREFIXMAP") {
    TryHotstring(":*?CR:" key, data)
  } else if (cmd == "PREFIX") {
    forcedDoublePrefixSubs := ""

    Loop Parse data ; Loop PREFIX's data line
    {
      if (Mod(A_Index, 2) == 1)
        continue

      trigger := SubStr(data, A_Index - 1, 1)
      subs := SubStr(data, A_Index, 1)

      if (PREFIX_CANCEL_MODE < 4) ; If PREFIX cancel mode has no timeout
        TryHotstring(":*?CR:" key trigger, subs) ; Registers default activation

      if (PREFIX_CANCEL_MODE == 2) { ; Space to confirm
        TryHotstring(":*?CB0:" key " ", SendBackSpace) ; BackSpace (right-to-left)
        ; TryHotstring(":*?CR:" key " ", key) ; BackSpace (left-to-right)
      } else if (PREFIX_CANCEL_MODE == 3) { ; Double prefix to confirm
        TryHotstring(":*?CR:" key key, key)
        if (key == trigger) ; Replacing with 'subs' has higher priority over confirming prefix
          forcedDoublePrefixSubs := subs
      } else if (PREFIX_CANCEL_MODE == 4) { ; Prefix timeout
        fn := SetPrefixTimeout.Bind(key)
        if (StrLen(key) == 1)
          TryHotkey("~" key, fn)
        else
          TryHotstring(":*?CB0:" key, fn)

        TryHotstring(":*?CB0:" key trigger, PrefixCheckTimeout.Bind(key, trigger))
        ; TryHotstring(":*?CR:" key " ", key) ; Makes it instantly cancellable with Space
      }
    } ; END Loop PREFIX's data line

    ; For cancel mode 3 (double prefix): sends a substitution instead of confirming the prefix
    if (forcedDoublePrefixSubs != "") {
      TryHotstring(":*?CR:" key key, forcedDoublePrefixSubs)
      TryHotstring(":*?CR:" key " ", key) ; Makes it instantly cancellable with Space
    }
    ; END PREFIX
  }
}

HotIf((*) => IsLayoutEnabled())

keyboardLayout := keyMap.Has("LAYOUT") ? keyMap["LAYOUT"].Get("2", "") : ""

Loop Parse keyboardLayout
{
  if (Mod(A_Index, 2) == 1)
    continue

  L := SubStr(keyboardLayout, A_Index - 1, 1)
  R := SubStr(keyboardLayout, A_Index, 1)
  fn := TranslateLayout.Bind(L, R)

  if IsUpper(L, "Locale")
    TryHotkey("+" L, fn)
  else
    TryHotkey(L, fn)
}

HotIf()

if (registrationErrors.Length) {
  msg := ""
  for line in registrationErrors
    msg .= line "`n"
  MsgBox("Some keymap entries could not be registered (" ACTIVE_KEYMAP "):`n`n" msg, "Windows Accent Layers", "Icon!")
}

#HotIf PREFIX_CANCEL_MODE != 0
~*Space::Hotstring("Reset")
#HotIf

Translate(map, char) {
  pos := InStr(map, char, true)
  return pos > 0 ? SubStr(map, pos + 1, 1) : char
}

PrefixCheckTimeout(prefix, trigger, *) {
  if (A_TickCount - pressTime.Get(prefix, 0) <= PREFIX_TIMEOUT) {
    SendInput("{BackSpace " (StrLen(prefix) + StrLen(trigger)) "}")
    Send("{Raw}" Translate(keyMap["PREFIX"][prefix], trigger))
  }

  if (prefix == trigger)
    Hotstring("Reset")
}

SetPrefixTimeout(prefix, *) {
  pressTime[prefix] := A_TickCount
}

TranslateLayout(L, R, *) {
  Send(R)
  ; Send("{Raw}" R)
}

CallAccentLayers(ThisHotkey) {
  Send("{Blind}{vkE8}") ; Masks Alt/Win release so apps (e.g. VS Code) don't open their menu bar
  KeyWait("Alt")
  KeyWait("LWin")
  KeyWait("RWin")

  ih := InputHook("L1 T" TIMEOUT, "{LCtrl}{RCtrl}{LAlt}{RAlt}{LWin}{RWin}")
  ih.VisibleNonText := false ; Block all keys while waiting, like v1's Input
  ih.Start()
  ih.Wait()
  c := ih.Input

  if (c == " ") {
    spaceChar := keyMap["SPACE"].Get(ThisHotkey, "")
    Send("{Raw}" (spaceChar != "" ? spaceChar : c))
  } else if (ih.EndReason = "Timeout") {
    Send("{Raw}" keyMap["TIMEOUT"].Get(ThisHotkey, ""))
  } else if (ih.EndReason != "Max") {
    return
  } else {
    SendInput(Translate(keyMap["LAYER"][ThisHotkey], c))
  }
}

CallMap(ThisHotkey) {
  Send("{Blind}{vkE8}") ; Masks Alt/Win release (see CallAccentLayers)
  Send("{Raw}" keyMap["MAP"][ThisHotkey])
}

SendBackSpace(*) {
  SendInput("{BackSpace}")
}

; neo-mousekeys interoperability
#HotIf NEOMOUSEKEYS_SUPPORT
~^e:: {
  global enabled := false
}

~Capslock:: {
  global enabled := true
}
#HotIf

UpdateLayoutOSD() {
  if (LAYOUT_SWITCH_SHOW_OSD)
    ShowMessage(secondaryLayout ? LAYOUT_2_NAME : LAYOUT_1_NAME, "White", LAYOUT_SWITCH_OSD_TIMEOUT)
}

SwitchLayout(*) {
  global secondaryLayout
  Send("{Blind}{vkE8}") ; Fixes alt-menu issues
  secondaryLayout := not secondaryLayout
  UpdateLayoutOSD()
}

#Include show-message.ahk
