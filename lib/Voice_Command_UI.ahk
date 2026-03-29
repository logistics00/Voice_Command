;================= VC_UI.ahk =================
; User Interface & Visuals voor Voice Command
; Bevat: Tray Menu, Status Circle, Command Manager GUI, Microphone Settings GUI
;=============================================

;============================================================
; TRAY MENU
;============================================================

/** @description SetupTrayMenu - Build the system tray context menu */
SetupTrayMenu() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Hotkey Settings", HotkeyMenu)
    A_TrayMenu.Add("Command Settings", CmdMenu)
    A_TrayMenu.Add("Microphone Settings", MicMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reload Commands", ReloadCommandsMenu)
    A_TrayMenu.Add("Edit INI File", EditIniMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Toggle Listening (F1)", ToggleListeningMenu)
    A_TrayMenu.Add("Toggle Logging", ToggleLoggingMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", ExitMenu)

    A_TrayMenu.Default := "Command Settings"
}

; Tray Menu Callbacks
HotkeyMenu(*) {
    HotkeyCmdMicGui(1)
}
CmdMenu(*) {
    HotkeyCmdMicGui(2)
}
MicMenu(*) {
    HotkeyCmdMicGui(3)
}

ReloadCommandsMenu(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapCommands

    mapCommands := LoadCommandsFromIni()
    RebuildGrammar()

    MsgBox("Commands reloaded: " mapCommands.Count " commands", "Reload Complete", "Iconi")
}

EditIniMenu(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile

    try {
        Run("notepad.exe " strIniFile)
    } catch as err {
        MsgBox("Failed to open INI file: " err.Message, "Error", "Icon!")
    }
}

ToggleListeningMenu(*) {
    ToggleListening()
}

ToggleLoggingMenu(*) {
    ToggleLogging()
}

ToggleLogging() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global intLoggingType, strIniFile

    if (intLoggingType = 0)
        intLoggingType := 7   ; restore full logging (flow + debug + error)
    else
        intLoggingType := 0   ; disable logging

    IniWrite(intLoggingType, strIniFile, 'Settings', 'loggingType')
    MsgBox("Logging is now " (intLoggingType > 0 ? "ON" : "OFF"), "Logging Toggle", "Iconi")
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Logging toggled: " intLoggingType, 2)
}

ExitMenu(*) {
    static blnExiting := false
    if (blnExiting)
        return
    blnExiting := true
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    CleanupVoice('User Exit', 0)
}

;============================================================
; TRAY ICON & TOGGLE LISTENING
;============================================================

/** @description UpdateTrayIcon - Update tray icon and status circle based on listening state */
UpdateTrayIcon() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global blnListening
    global strIconListening, intIconListeningNum
    global strIconNotListening, intIconNotListeningNum

    if (blnListening) {
        TraySetIcon(strIconListening, intIconListeningNum)
        A_IconTip := "Voice Command - Listening (Active)"
    } else {
        TraySetIcon(strIconNotListening, intIconNotListeningNum)
        A_IconTip := "Voice Command - NOT Listening"
    }

    UpdateStatusCircle()
}

/** @description ToggleListening - Toggle voice command listening state on/off */
ToggleListening() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objGrammar, blnListening

    blnListening := !blnListening

    if (blnListening) {
        ; Enable grammar
        objGrammar.CmdSetRuleState("cmd", 1)
        pool.ShowByMouse('🎤 Listening ON', 2000)
        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Listening toggled ON via F1", 2)
    } else {
        ; Disable grammar
        objGrammar.CmdSetRuleState("cmd", 0)
        pool.ShowByMouse('🔇 Listening OFF', 2000)
        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Listening toggled OFF via F1", 2)
    }

    UpdateTrayIcon()
}

;============================================================
; STATUS CIRCLE OVERLAY
;============================================================

/** @description GetStatusLabel - Return language label for Vosk/Whisper modes
    @returns {string} - "EN", "NL", etc. when in Vosk/Whisper; "" otherwise */
GetStatusLabel() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strVoiceMode, speakLanguage, strSpecialLanguage

    if (strVoiceMode = "vosk" || strVoiceMode = "dictate") {
        if (speakLanguage = "special" && strSpecialLanguage != "")
            return StrUpper(strSpecialLanguage)
        return "EN"
    }
    return ""
}

/** @description GetStatusColor - Return circle color for the current voice mode
    @returns {string} - Hex color code without '#'
    @details - strVoiceMode drives color: sapi=blue, vosk=green, dictate=purple
             - blnListening=false overrides to red regardless of mode */
GetStatusColor() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global blnListening, strVoiceMode
    global strColorListening, strColorNotListening, strColorVosk, strColorWhisper

    if (!blnListening)
        return strColorNotListening     ; Red — F1 listening OFF

    switch strVoiceMode {
        case "vosk":    return strColorVosk             ; Green
        case "dictate": return strColorWhisper          ; Purple
        default:        return strColorListening        ; Blue — SAPI active
    }
}

/** @description CreateStatusCircle - Create the visual status circle overlay window */
CreateStatusCircle() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objStatusCircle, intCircleSize, intCircleMargin

    ; Calculate position in upper right corner
    intXPos := A_ScreenWidth - intCircleMargin - (intCircleSize // 2)
    intYPos := intCircleMargin + (intCircleSize // 2)

    objStatusCircle := ShowCircle(intCircleSize, GetStatusColor(), intXPos, intYPos, GetStatusLabel())
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Status circle created at " intXPos ", " intYPos, 2)
}

/** @description UpdateStatusCircle - Update status circle color when listening state changes */
UpdateStatusCircle() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objStatusCircle, intCircleSize, intCircleMargin

    ; If circle doesn't exist yet, create it
    if (objStatusCircle = "") {
        CreateStatusCircle()
        return
    }

    ; Destroy old circle and create new one with updated color
    try {
        objStatusCircle.Destroy()
    }

    ; Calculate position in upper right corner
    intXPos := A_ScreenWidth - intCircleMargin - (intCircleSize // 2)
    intYPos := intCircleMargin + (intCircleSize // 2)

    ; Create the circle with new color and language label
    objStatusCircle := ShowCircle(intCircleSize, GetStatusColor(), intXPos, intYPos, GetStatusLabel())
}

/** @description ShowCircle - Create and display a colored circle GUI element
    @param {integer} circleSize - Diameter of the circle in pixels
    @param {string} circleColor - Hex color code without '#'
    @param {integer} xPos - X coordinate for circle center
    @param {integer} yPos - Y coordinate for circle center
    @param {string} strLabel - Optional language label drawn in center (e.g. "EN", "NL")
    @returns {object} - GUI object reference */
ShowCircle(circleSize := 50, circleColor := "FF0000", xPos := "", yPos := "", strLabel := "") {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    if (xPos = "") {
        xPos := A_ScreenWidth // 2
    }
    if (yPos = "") {
        yPos := A_ScreenHeight // 2
    }

    leftPos := xPos - (circleSize // 2)
    topPos := yPos - (circleSize // 2)

    objCircleGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
    objCircleGui.BackColor := circleColor

    if (strLabel != "") {
        intFontSize := Max(8, circleSize // 4)
        intFontHeight := Round(intFontSize * 96 / 72)
        intYOffset := (circleSize - intFontHeight) // 2
        objCircleGui.SetFont("s" intFontSize " Bold cFFFFFF")
        objCircleGui.AddText("x0 y" intYOffset " w" circleSize " Center", strLabel)
    }

    objCircleGui.Show("x" leftPos " y" topPos " w" circleSize " h" circleSize " NoActivate")

    hRegion := DllCall("CreateEllipticRgn",
        "Int", 0, "Int", 0, "Int", circleSize, "Int", circleSize, "Ptr")

    DllCall("SetWindowRgn",
        "Ptr", objCircleGui.Hwnd, "Ptr", hRegion, "Int", 1)

    return objCircleGui
}

;============================================================
; HotkeyCmdMic GUI
;============================================================

/** @description HotkeyCmdMicGui - Show the unified Hotkeys/Commands/Microphone GUI
    @param {integer} defaultTab - Tab to show on open: 1=Commands, 2=Microphone (default: 1) */
HotkeyCmdMicGui(defaultTab := 1) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global goo, objManagerTab
    global edtCommand, ddlType, edtAction
    global mapCommands, lv1, lv1Row
    global strIniFile
    global objRecognizer, intCurrentMicIndex, strCurrentMicName
    global objTxtMicStatus
    global fltConfidenceThreshold, blnShowConfidence, objTxtThreshold
    global radDictateFW, radDictateOpenAI, radDictateP2, radDictateP3, edtApiKey

    ; If GUI already exists, switch to requested tab and show
    if (goo != "") {
        objManagerTab.Value := defaultTab
        goo.Show()
        return
    }

    guiWidth := Integer(IniRead(strIniFile, "Gui", "width", 1000))
    widthCol4 := Integer(IniRead(strIniFile, "Gui", "width_col4", 600))
    widthCol1 := 150
    ; widthCol1 := (guiWidth - widthCol4) // 3
    lv1Row := 0

    goo := Gui('+Resize', 'Voice Command Manager')
    goo.BackColor := '0x00C0C0'
    goo.SetFont('s12 w700', 'Calibri')
    goo.OnEvent('Close', HotkeyCmdMicGuiClose)

    ; Tab control — must be added before all tab content
    tab := goo.AddTab3('x10 y+m w' guiWidth - 100, ['Hotkeys', 'Commands', 'Microphone'])

    ;----------------------------------------------------------
    ; TAB 1 — Hotkeys
    ;----------------------------------------------------------

	tab.UseTab(1)

	goo.AddText('x30 y+m', 'If you know how HotKeys in AHK work, you may change the defaults.')
    goo.AddText('x30 y+m', 'At start, "Resulting HotKey" contains the actual HotKey.')
    ; goo.SetFont('s12 cYellow w1000', 'Calibri')
    goo.AddText('x30 y+m w150', 'Toggle Listening')
    strHotkey := IniRead(strIniFile, 'HotKeys', 'listening')
    global cbListeningWin := goo.AddCheckbox((InStr(strHotkey, '#') ? 'x+m yp Checked' : 'x+m yp'), 'Win')
    global cbListeningCtrl := goo.AddCheckbox((InStr(strHotkey, '^') ? 'x+m yp Checked' : 'x+m yp'), 'Ctrl')
    global cbListeningShift := goo.AddCheckbox((InStr(strHotkey, '+') ? 'x+m yp Checked' : 'x+m yp'), 'Shift')
    global cbListeningAlt := goo.AddCheckbox((InStr(strHotkey, '!') ? 'x+m yp Checked' : 'x+m yp'), 'Alt')
    goo.AddText('x+m yp', 'Resulting HotKey:')
    global edtListening := goo.AddEdit('x+m yp w150 Background0x00F0F0', strHotkey)
    goo.AddButton('x+m yp h25', 'Save Hotkey').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtListening, 'listening'))
    cbListeningWin.OnEvent('Click', (*) => UpdateHotkey(cbListeningWin, edtListening, '#', 'listening'))
    cbListeningCtrl.OnEvent('Click', (*) => UpdateHotkey(cbListeningCtrl, edtListening, '^', 'listening'))
    cbListeningShift.OnEvent('Click', (*) => UpdateHotkey(cbListeningShift, edtListening, '+', 'listening'))
    cbListeningAlt.OnEvent('Click', (*) => UpdateHotkey(cbListeningAlt, edtListening, '!', 'listening'))
    goo.AddText('x30 y+m w150', 'Show MainGui')
    strHotkey := IniRead(strIniFile, 'HotKeys', 'mainGui')
    global cbMainGuiWin := goo.AddCheckbox((InStr(strHotkey, '#') ? 'x+m yp Checked' : 'x+m yp'), 'Win')
    global cbMainGuiCtrl := goo.AddCheckbox((InStr(strHotkey, '^') ? 'x+m yp Checked' : 'x+m yp'), 'Ctrl')
    global cbMainGuiShift := goo.AddCheckbox((InStr(strHotkey, '+') ? 'x+m yp Checked' : 'x+m yp'), 'Shift')
    global cbMainGuiAlt := goo.AddCheckbox((InStr(strHotkey, '!') ? 'x+m yp Checked' : 'x+m yp'), 'Alt')
    goo.AddText('x+m yp', 'Resulting HotKey:')
    global edtMainGui := goo.AddEdit('x+m yp w150 Background0x00F0F0', strHotkey)
    goo.AddButton('x+m yp h25', 'Save Hotkey').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtMainGui, 'mainGui'))
    cbMainGuiWin.OnEvent('Click', (*) => UpdateHotkey(cbMainGuiWin, edtMainGui, '#', 'mainGui'))
    cbMainGuiCtrl.OnEvent('Click', (*) => UpdateHotkey(cbMainGuiCtrl, edtMainGui, '^', 'mainGui'))
    cbMainGuiShift.OnEvent('Click', (*) => UpdateHotkey(cbMainGuiShift, edtMainGui, '+', 'mainGui'))
    cbMainGuiAlt.OnEvent('Click', (*) => UpdateHotkey(cbMainGuiAlt, edtMainGui, '!', 'mainGui'))
    goo.AddText('x30 y+m w150', 'Cycle Modi')
    strHotkey := IniRead(strIniFile, 'HotKeys', 'modus')
    global cbModusWin := goo.AddCheckbox((InStr(strHotkey, '#') ? 'x+m yp Checked' : 'x+m yp'), 'Win')
    global cbModusCtrl := goo.AddCheckbox((InStr(strHotkey, '^') ? 'x+m yp Checked' : 'x+m yp'), 'Ctrl')
    global cbModusShift := goo.AddCheckbox((InStr(strHotkey, '+') ? 'x+m yp Checked' : 'x+m yp'), 'Shift')
    global cbModusAlt := goo.AddCheckbox((InStr(strHotkey, '!') ? 'x+m yp Checked' : 'x+m yp'), 'Alt')
    goo.AddText('x+m yp', 'Resulting HotKey:')
    global edtModus := goo.AddEdit('x+m yp w150 Background0x00F0F0', strHotkey)
    goo.AddButton('x+m yp h25', 'Save Hotkey').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtModus, 'modus'))
    cbModusWin.OnEvent('Click', (*) => UpdateHotkey(cbModusWin, edtModus, '#', 'modus'))
    cbModusCtrl.OnEvent('Click', (*) => UpdateHotkey(cbModusCtrl, edtModus, '^', 'modus'))
    cbModusShift.OnEvent('Click', (*) => UpdateHotkey(cbModusShift, edtModus, '+', 'modus'))
    cbModusAlt.OnEvent('Click', (*) => UpdateHotkey(cbModusAlt, edtModus, '!', 'modus'))
    goo.AddText('x30 y+m w150', 'Toggle Language')
    strHotkey := IniRead(strIniFile, 'HotKeys', 'language')
    global cbLanguageWin := goo.AddCheckbox((InStr(strHotkey, '#') ? 'x+m yp Checked' : 'x+m yp'), 'Win')
    global cbLanguageCtrl := goo.AddCheckbox((InStr(strHotkey, '^') ? 'x+m yp Checked' : 'x+m yp'), 'Ctrl')
    global cbLanguageShift := goo.AddCheckbox((InStr(strHotkey, '+') ? 'x+m yp Checked' : 'x+m yp'), 'Shift')
    global cbLanguageAlt := goo.AddCheckbox((InStr(strHotkey, '!') ? 'x+m yp Checked' : 'x+m yp'), 'Alt')
    goo.AddText('x+m yp', 'Resulting HotKey:')
    global edtLanguage := goo.AddEdit('x+m yp w150 Background0x00F0F0', strHotkey)
    goo.AddButton('x+m yp h25', 'Save Hotkey').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtLanguage, 'language'))
    cbLanguageWin.OnEvent('Click', (*) => UpdateHotkey(cbLanguageWin, edtLanguage, '#', 'language'))
    cbLanguageCtrl.OnEvent('Click', (*) => UpdateHotkey(cbLanguageCtrl, edtLanguage, '^', 'language'))
    cbLanguageShift.OnEvent('Click', (*) => UpdateHotkey(cbLanguageShift, edtLanguage, '+', 'language'))
    cbLanguageAlt.OnEvent('Click', (*) => UpdateHotkey(cbLanguageAlt, edtLanguage, '!', 'language'))

    ;----------------------------------------------------------
    ; TAB 2 — Commands
    ;----------------------------------------------------------
    tab.UseTab(2)

    goo.AddText("x30 y+m", "Command:")
    goo.AddText("x+90 yp", "Type:")
    goo.AddText("x+80 yp", "Action:")
    edtCommand := goo.AddEdit("x30 y+0 w150 Background0x00F0F0")
    ddlType := goo.AddDropDownList("x+m yp w100 Background0x00F0F0", ["Run", "File", "WinClose", "Send", "Mouse", "MsgBox", "Function"])
    edtAction := goo.AddEdit("x+m yp w" widthCol4 " Background0x00F0F0")

    btnAdd := goo.AddButton("x30 y+m w80 h30", "Add")
    btnAdd.OnEvent("Click", AddCommand)
    btnEdit := goo.AddButton("x+m yp w80 h30", "Update")
    btnEdit.OnEvent("Click", EditCommand)
    btnDelete := goo.AddButton("x+m yp w80 h30", "Delete")
    btnDelete.OnEvent("Click", DeleteCommand)
    btnClear := goo.AddButton("x+m yp w80 h30", "Clear")
    btnClear.OnEvent("Click", ClearFields)

    strLvOptions := "x30 y+40 w" guiWidth - 170 " r30 BackGround0x00F0F0 Grid LV0x20"
    lv1 := goo.AddListView(strLvOptions, ["Command", "Type", "Action"])
    lv1.OnEvent("Click", CommandListClick)
    lv1.OnEvent("DoubleClick", CommandListDoubleClick)

    RefreshCommandList()

    lv1.ModifyCol(1, '150 sort')
    lv1.ModifyCol(2, '100 sort')
    lv1.ModifyCol(3, widthCol4)

    ;----------------------------------------------------------
    ; TAB 3 — Microphone Settings
    ;----------------------------------------------------------
    tab.UseTab(3)

    goo.AddText('x30 y+m+20', 'Select your microphone for voice recognition:')
    objTxtMicStatus := goo.AddText('x+m yp', '[Current: ' strCurrentMicName ']')
    lv2 := goo.AddListView('x30 y+m w400 r4 -Multi Background0x00F0F0', ['#', 'Microphone Name'])
    lv2.OnEvent('Click', MicListClick)

    try {
        objAudioInputs := objRecognizer.GetAudioInputs()
        Loop objAudioInputs.Count {
            intIdx := A_Index - 1
            strMicName := objAudioInputs.Item(intIdx).GetDescription()
            lv2.Add("", intIdx, strMicName)
            if (intIdx = intCurrentMicIndex)
                lv2.Modify(A_Index, "+Select +Focus")
        }
    }
    lv2.ModifyCol(1, 30)
    lv2.ModifyCol(2, 360)

    goo.AddButton('x+m yp h30', 'Save Microphone Settings').OnEvent('Click', SaveMicSettings)
	goo.AddGroupBox('x20 y40 w700 h190', 'Microphone Selection')

    objTxtThreshold := goo.AddText('x30 y+m+20', 'Threshold: ')
    sliderThreshold := goo.AddSlider('x+m yp w400 Range0-100 TickInterval10 Line1 Page5', Round(fltConfidenceThreshold * 100))
    sliderThreshold.OnEvent('Change', OnThresholdSliderChange)
    objTxtThreshold := goo.AddText('x+m yp', Round(fltConfidenceThreshold * 100) '%')
    goo.AddText('x30 y+m cRed', 'Drag to set the minimum confidence (%) for a recognition to be accepted.')
    chkShowConfidence := goo.AddCheckbox('x30 y+m', 'Show confidence % in tooltips')
    chkShowConfidence.Value := blnShowConfidence ? 1 : 0
    chkShowConfidence.OnEvent('Click', OnShowConfidenceClick)
    goo.AddGroupBox('x20 y235 w700 h120', 'SAPI Threshold and Confidence')

    strDictateMode := IniRead(strIniFile, 'Settings', 'dictateMode', 'faster-whisper')
    strApiKey := IniRead(strIniFile, 'Settings', 'openaiApiKey', '')

	radDictateFW     := goo.AddRadio('x40 y+m+50 Group', 'faster-whisper: local, offline, free, 99+ languages')
    radDictateOpenAI := goo.AddRadio('xp y+m',          'whisper-gpt-4o:  OpenAI cloud, $0.006/min, 99+ languages')
    radDictateP2     := goo.AddRadio('xp y+m',          'Parakeet v2:     local, offline, free, English only')
    radDictateP3     := goo.AddRadio('xp y+m',          'Parakeet v3:     local, offline, free, 25 languages')
    radDictateFW.Value     := (strDictateMode = 'faster-whisper') ? 1 : 0
    radDictateOpenAI.Value := (strDictateMode = 'whisper-gpt-4o') ? 1 : 0
    radDictateP2.Value     := (strDictateMode = 'parakeet-v2')    ? 1 : 0
    radDictateP3.Value     := (strDictateMode = 'parakeet-v3')    ? 1 : 0
    radDictateFW.OnEvent('Click',     OnDictateModeChange)
    radDictateOpenAI.OnEvent('Click', OnDictateModeChange)
    radDictateP2.OnEvent('Click',     OnDictateModeChange)
    radDictateP3.OnEvent('Click',     OnDictateModeChange)
    goo.AddGroupBox('x30 y390 w600 h140', 'Choose Grammar')

	goo.AddText('x30 y+m+10', 'OpenAI API Key (when choice for whisper-gpt-4o):')
    edtApiKey := goo.AddEdit('x+m yp w300 Background0x00F0F0', strApiKey)
    edtApiKey.Enabled := (strDictateMode = 'whisper-gpt-4o')
    goo.AddButton('x30 y+m w160 h30', 'Save Dictate Settings').OnEvent('Click', SaveDictateSettings)
    goo.AddGroupBox('x20 y365 w700 h270', 'Dictate Backend')

    tab.UseTab(0)											; close construction context
    tab.Value := defaultTab									; select correct tab
    goo.Show('AutoSize Center')
}

UpdateHotkey(cb, edt, token, type) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
	alreadyIn := InStr(edt.Value, token)
	if (cb.Value) && !alreadyIn
		edt.Value := token . edt.Value
	else if !cb.Value && alreadyIn
		edt.Value := StrReplace(edt.Value, token, '')
}

/** @description HotkeyCmdMicGuiClose - Close handler: check for unsaved hotkey changes, then destroy GUI */
HotkeyCmdMicGuiClose(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global goo, strIniFile
    global edtListening, edtMainGui, edtModus, edtLanguage

    ; Compare each edit field to the saved INI value
    strIniListening := IniRead(strIniFile, 'HotKeys', 'listening')
    strIniMainGui   := IniRead(strIniFile, 'HotKeys', 'mainGui')
    strIniModus     := IniRead(strIniFile, 'HotKeys', 'modus')
    strIniLanguage  := IniRead(strIniFile, 'HotKeys', 'language')

    blnChanged := (edtListening.Value != strIniListening)
               || (edtMainGui.Value   != strIniMainGui)
               || (edtModus.Value     != strIniModus)
               || (edtLanguage.Value  != strIniLanguage)

    if (blnChanged) {
        intResult := MsgBox('You have unsaved changes — Save or Discard?', 'Unsaved Changes', 'YesNo Icon? Default1')
        ; Yes = Save, No = Discard
        if (intResult = 'Yes') {
            if (edtListening.Value != strIniListening)
                UpdateHotkeyEdtField(edtListening, 'listening')
            if (edtMainGui.Value != strIniMainGui)
                UpdateHotkeyEdtField(edtMainGui, 'mainGui')
            if (edtModus.Value != strIniModus)
                UpdateHotkeyEdtField(edtModus, 'modus')
            if (edtLanguage.Value != strIniLanguage)
                UpdateHotkeyEdtField(edtLanguage, 'language')
        }
    }

    goo.Destroy()
    goo := ""
}

UpdateHotkeyEdtField(edt, type) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
	if CheckHotkey(edt.Value, ' is wrong. ') = false {
		return
	}

	Hotkey(IniRead(strIniFile, 'HotKeys', type), 'Off')

	IniWrite(edt.Value, strIniFile, 'HotKeys', type)
	Hotkey(IniRead(strIniFile, 'HotKeys', type), 'On')

	Switch type {
		case 'listening':
			Hotkey(IniRead(strIniFile, 'HotKeys', 'listening'), ToggleListeningMenu)
		case 'mainGui':
			Hotkey(IniRead(strIniFile, 'HotKeys', 'mainGui'), HotkeyMenu)
		case 'modus':
			Hotkey(IniRead(strIniFile, 'HotKeys', 'modus'), CycleVoiceMode)
		case 'language':
			Hotkey(IniRead(strIniFile, 'HotKeys', 'language'), ToggleLanguage)
	}
}

CheckHotkey(strKey, message) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
	try {
		Hotkey(strKey, (*) => {})
		return true
	} catch as err {
		MsgBox('Newer hotkey "' strKey '"' message '`nError: ' . err.Message, 'Hotkey error', 'Icon!')
		return false
	}
}

/** @description RefreshCommandList - Refresh Command List in ListView */
RefreshCommandList() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global lv1, mapCommands

    if (lv1 = "") {
        return
    }

    lv1.Delete()

    for strPhrase, strActionData in mapCommands {
        arrayParts := StrSplit(strActionData, "|", , 2)

        if (arrayParts.Length = 2) {
            strType := arrayParts[1]
            strAction := arrayParts[2]
        } else {
            strType := ""
            strAction := strActionData
        }

        lv1.Add("", strPhrase, strType, strAction)
    }
}

; Command List Click - Populate Fields
CommandListClick(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global edtCommand, ddlType, edtAction, lv1, lv1Row

    lv1Row := lv1.GetNext(0, "Focused")
    if (lv1Row > 0) {
        edtCommand.Value	:= lv1.GetText(lv1Row, 1)
        ddlType.Text		:= lv1.GetText(lv1Row, 2)
        edtAction.Value		:= lv1.GetText(lv1Row, 3)
    }
}

; Command List Double-Click
CommandListDoubleClick(*) {
    CommandListClick()
}

; Add Command
AddCommand(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global edtCommand, ddlType, edtAction
    global mapCommands, strIniFile

    strPhrase := Trim(edtCommand.Value)
    strType := ddlType.Text
    strAction := Trim(edtAction.Value)

    if (strPhrase = "" || strAction = "") {
        MsgBox("Please enter both 'Words Said' and 'Action'.", "Missing Input", "Icon!")
        return
    }

    strActionData := strType "|" strAction
    mapCommands[StrLower(strPhrase)] := strActionData

    ; Save to INI
    IniWrite(strActionData, strIniFile, "Commands", strPhrase)

    RefreshCommandList()
    ClearFields()

    ; Rebuild grammar
    RebuildGrammar()

    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Added command: " strPhrase " => " strActionData, 2)
}

; Edit Command
EditCommand(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global edtCommand, ddlType, edtAction, lv1, lv1Row
    global mapCommands, strIniFile

    if (lv1Row < 1) {
        MsgBox("Please select a command to edit.", "No Selection", "Icon!")
        return
    }

    strOldPhrase := lv1.GetText(lv1Row, 1)
    strPhrase := Trim(edtCommand.Value)
    strType := ddlType.Text
    strAction := Trim(edtAction.Value)

    if (strPhrase = "" || strAction = "") {
        MsgBox("Please enter both 'Words Said' and 'Action'.", "Missing Input", "Icon!")
        return
    }

    ; Remove old entry if phrase changed
    if (StrLower(strOldPhrase) != StrLower(strPhrase)) {
        mapCommands.Delete(StrLower(strOldPhrase))
        IniDelete(strIniFile, "Commands", strOldPhrase)
    }

    strActionData := strType "|" strAction
    mapCommands[StrLower(strPhrase)] := strActionData

    ; Save to INI
    IniWrite(strActionData, strIniFile, "Commands", strPhrase)

    RefreshCommandList()
    ClearFields()

    ; Rebuild grammar
    RebuildGrammar()

    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Updated command: " strPhrase " => " strActionData, 2)
}

; Delete Command
DeleteCommand(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapCommands, strIniFile, lv1, lv1Row

    if (lv1Row < 1) {
        MsgBox("Please select a command to delete.", "No Selection", "Icon!")
        return
    }

    strPhrase := lv1.GetText(lv1Row, 1)

    intResult := MsgBox("Delete command: " strPhrase "?", "Confirm Delete", "YesNo Icon?")
    if (intResult = "No") {
        return
    }

    mapCommands.Delete(StrLower(strPhrase))
    IniDelete(strIniFile, "Commands", strPhrase)

    RefreshCommandList()
    ClearFields()

    ; Rebuild grammar
    RebuildGrammar()

    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Deleted command: " strPhrase, 2)
}

; Clear Input Fields
ClearFields(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global edtCommand, ddlType, edtAction, lv1Row

    edtCommand.Value := ""
    ddlType.Choose(0)
    edtAction.Value := ""
    lv1Row := 0
}

; Microphone List Click Event
MicListClick(ctrl, info) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objTxtMicStatus, objRecognizer, intCurrentMicIndex, strCurrentMicName

    intRow := ctrl.GetNext(0, "Focused")
    if (intRow > 0) {
        intIdx := ctrl.GetText(intRow, 1)
        strName := ctrl.GetText(intRow, 2)

        intCurrentMicIndex := Integer(intIdx)
        strCurrentMicName := strName
        objTxtMicStatus.Text := "Selected: " strName

        ; Switch microphone immediately for testing
        try {
            objAudioInputs := objRecognizer.GetAudioInputs()
            objRecognizer.AudioInput := objAudioInputs.Item(intCurrentMicIndex)
            LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Switched to mic: " strName, 2)
        } catch as err {
            LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Failed to switch mic: " err.Message, 4)
        }
    }
}

; Save Microphone Settings
SaveMicSettings(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile, intCurrentMicIndex, strCurrentMicName

    try {
        IniWrite(strCurrentMicName, strIniFile, "Settings", "microphoneName")

        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Saved mic: [" intCurrentMicIndex "] " strCurrentMicName, 2)

        MsgBox("Microphone settings saved!`n`nMicrophone: " strCurrentMicName, "Settings Saved", "Iconi")
    } catch as err {
        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Failed to save: " err.Message, 4)
        MsgBox("Failed to save settings: " err.Message, "Error", "Icon!")
    }
}

/** @description OnThresholdSliderChange - Handle threshold slider movement */
OnThresholdSliderChange(ctrl, *) {
    global fltConfidenceThreshold, fltIniThreshold, strIniFile
    global intAdaptN, fltAdaptSum, objTxtThreshold

    intPct := ctrl.Value
    fltConfidenceThreshold := intPct / 100
    fltIniThreshold        := intPct / 100
    intAdaptN   := 0
    fltAdaptSum := 0.0

    IniWrite(intPct, strIniFile, "Settings", "confidenceThreshold")

    objTxtThreshold.Text := 'Threshold: ' intPct '%'
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Threshold set by slider to ' intPct '%', 2)
}

/** @description OnShowConfidenceClick - Handle show-confidence checkbox toggle */
OnShowConfidenceClick(ctrl, *) {
    global blnShowConfidence, strIniFile

    blnShowConfidence := (ctrl.Value = 1)
    IniWrite(blnShowConfidence ? "1" : "0", strIniFile, "Settings", "showConfidence")
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'ShowConfidence set to ' (blnShowConfidence ? 'ON' : 'OFF'), 2)
}

/** @description OnDictateModeChange - Enable/disable API key field based on backend selection */
OnDictateModeChange(ctrl, *) {
    global edtApiKey, radDictateOpenAI

    edtApiKey.Enabled := (radDictateOpenAI.Value = 1)
}

/** @description SaveDictateSettings - Save dictate backend and API key to INI */
SaveDictateSettings(*) {
    global strIniFile, radDictateFW, radDictateOpenAI, radDictateP2, radDictateP3, edtApiKey

    if (radDictateOpenAI.Value)
        strMode := 'whisper-gpt-4o'
    else if (radDictateP2.Value)
        strMode := 'parakeet-v2'
    else if (radDictateP3.Value)
        strMode := 'parakeet-v3'
    else
        strMode := 'faster-whisper'

    strKey := Trim(edtApiKey.Value)

    IniWrite(strMode, strIniFile, 'Settings', 'dictateMode')
    IniWrite(strKey,  strIniFile, 'Settings', 'openaiApiKey')

    pool.ShowByMouse('Dictate settings saved. Press F3 twice to apply if Dictate is active.', 3000)
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Dictate mode set to ' strMode, 2)

    ; If a Parakeet mode was selected, check whether model files are present
    if (strMode = 'parakeet-v2' || strMode = 'parakeet-v3') {
        strVersion  := (strMode = 'parakeet-v2') ? 'v2' : 'v3'
        strSizeMB   := (strMode = 'parakeet-v2') ? '~640 MB' : '~650 MB'
        strModelDir := A_ScriptDir '\models\parakeet\' strVersion
        if (!FileExist(strModelDir '\tokens.txt')) {
            intAnswer := MsgBox('Parakeet ' strVersion ' model files are not installed.`nDownload size: ' strSizeMB '`n`nDownload now?',
                'Voice Command — Parakeet ' strVersion ' model missing', 'OKCancel Icon?')
            if (intAnswer = 'OK')
                Run('python "' A_ScriptDir '\python\download_parakeet.py" ' strVersion,, 'Show')
        }
    }
}

;================= End of VC_UI.ahk =================
