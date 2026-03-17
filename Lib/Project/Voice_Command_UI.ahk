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
    global blnLogEnabled, strIniFile

    blnLogEnabled := !blnLogEnabled

    try {
        IniWrite(blnLogEnabled ? "1" : "0", strIniFile, "Settings", "logEnabled")
    }

    MsgBox("Logging is now " (blnLogEnabled ? "ON" : "OFF"), "Logging Toggle", "Iconi")
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Logging toggled: " (blnLogEnabled ? "ON" : "OFF"), 2)
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
    global objGrammar, objControlGrammar, blnListening, intTestMode

    if (intTestMode) {
        ToolTip("Cannot toggle in Test Mode")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    blnListening := !blnListening

    if (blnListening) {
        ; Enable both grammars
        objGrammar.CmdSetRuleState("cmd", 1)
        try { objControlGrammar.CmdSetRuleState("control", 1) }
        ToolTip("🎤 Listening ON")
        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Listening toggled ON via F1", 2)
    } else {
        ; Disable both grammars
        objGrammar.CmdSetRuleState("cmd", 0)
        objControlGrammar.CmdSetRuleState("control", 0)
        ToolTip("🔇 Listening OFF")
        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Listening toggled OFF via F1", 2)
    }

    UpdateTrayIcon()
    SetTimer(() => ToolTip(), -2000)
}

;============================================================
; STATUS CIRCLE OVERLAY
;============================================================

/** @description GetStatusLabel - Return language label for Vosk/Whisper modes
    @returns {string} - "EN", "NL", etc. when in Vosk/Whisper; "" otherwise */
GetStatusLabel() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strVoiceMode, speakLanguage, strSpecialLanguage

    if (strVoiceMode = "vosk" || strVoiceMode = "whisper") {
        if (speakLanguage = "special" && strSpecialLanguage != "")
            return StrUpper(strSpecialLanguage)
        return "EN"
    }
    return ""
}

/** @description GetStatusColor - Return circle color for the current voice mode
    @returns {string} - Hex color code without '#'
    @details - strVoiceMode drives color: sapi=blue, vosk=green, whisper=purple
             - blnListening=false overrides to red regardless of mode */
GetStatusColor() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global blnListening, strVoiceMode
    global strColorListening, strColorNotListening, strColorVosk, strColorWhisper

    if (!blnListening)
        return strColorNotListening     ; Red — F1 listening OFF

    switch strVoiceMode {
        case "vosk":    return strColorVosk             ; Green
        case "whisper": return strColorWhisper          ; Purple
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
; COMMAND MANAGER GUI
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
    global objProgressLevel, objTxtLevelPercent, objTxtMicStatus, objTxtTestResult
    global objSliderThreshold, objTxtThresholdValue, objChkshowConfidence
    global fltConfidenceThreshold, blnShowConfidence

    ; If GUI already exists, switch to requested tab and show
    if (goo != "") {
        objManagerTab.Value := defaultTab
        SetTimer(UpdateAudioLevel, defaultTab = 3 ? 100 : 0)
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

    ; ; Tab control — must be added before all tab content
    ; tab := goo.AddTab3('x0 y0 w' guiWidth, ['Commands', 'Microphone'])
    ; tab.OnEvent('Change', TabChanged)
    ; objManagerTab := tab

    ; ;----------------------------------------------------------
    ; ; TAB 1 — Commands (Hotkeys + Add/Edit + ListView)
    ; ;----------------------------------------------------------
    ; tab.UseTab(1)
    ; Tab control — must be added before all tab content
    tab := goo.AddTab3('x10 y+m w' guiWidth, ['Hotkeys', 'Commands', 'Microphone'])
    tab.OnEvent('Change', (ctrl, *) => SetTimer(UpdateAudioLevel, ctrl.Value = 3 ? 100 : 0))
    ; objManagerTab := tab

    ;----------------------------------------------------------
    ; TAB 1 — Commands (Hotkeys + Add/Edit + ListView)
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
    goo.AddButton('x+m yp h25', 'Reset').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtListening, 'listening'))
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
    goo.AddButton('x+m yp h25', 'Reset').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtMainGui, 'mainGui'))
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
    goo.AddButton('x+m yp h25', 'Reset').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtModus, 'modus'))
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
    goo.AddButton('x+m yp h25', 'Reset').OnEvent('Click', (*) => UpdateHotkeyEdtField(edtLanguage, 'language'))
    cbLanguageWin.OnEvent('Click', (*) => UpdateHotkey(cbLanguageWin, edtLanguage, '#', 'language'))
    cbLanguageCtrl.OnEvent('Click', (*) => UpdateHotkey(cbLanguageCtrl, edtLanguage, '^', 'language'))
    cbLanguageShift.OnEvent('Click', (*) => UpdateHotkey(cbLanguageShift, edtLanguage, '+', 'language'))
    cbLanguageAlt.OnEvent('Click', (*) => UpdateHotkey(cbLanguageAlt, edtLanguage, '!', 'language'))

	; goo.AddGroupBox('x30 y50 r7 w850', 'Hotkeys')

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

    strLvOptions := "x30 y+40 w" guiWidth - 30 " r30 BackGround0x03f68f Grid LV0x20"
    lv1 := goo.AddListView(strLvOptions, ["Command", "Type", "Action"])
    lv1.OnEvent("Click", CommandListClick)
    lv1.OnEvent("DoubleClick", CommandListDoubleClick)

    ; goo.AddGroupBox('x30 y50 r4 w900', 'Add / Edit Command')

    RefreshCommandList()

    lv1.ModifyCol(1, '150 sort')
    lv1.ModifyCol(2, '100 sort')
    lv1.ModifyCol(3, widthCol4)
    ; lv1.ModifyCol(1, widthCol1)
    ; lv1.ModifyCol(2, widthCol1)
    ; lv1.ModifyCol(3, widthCol4)
    ; lv1.ModifyCol(4, widthCol4)

    ;----------------------------------------------------------
    ; TAB 2 — Microphone Settings
    ;----------------------------------------------------------
    tab.UseTab(3)

    goo.AddText('x30 y+m', 'Select your microphone for voice recognition:')
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

    goo.AddText('x30 y+m+30', 'Audio Level (speak to test):')
    objProgressLevel := goo.AddProgress('x+m yp w400 h20 Range0-100 Background0x00F0F0', 0)
    objTxtLevelPercent := goo.AddText('x+m yp', 'Level: 0%')

    goo.AddText('x30 y+m+30', 'Confidence Threshold (reject below this %):')
    intCurrentThreshold := Round(fltConfidenceThreshold * 100)
    objSliderThreshold := goo.AddSlider('x+m yp w300 Range0-100 TickInterval10 AltSubmit Background0x00F0F0', intCurrentThreshold)
    objSliderThreshold.OnEvent('Change', ThresholdSliderChange)
    objTxtThresholdValue := goo.AddText('x+m yp w50', intCurrentThreshold '%')

    objChkshowConfidence := goo.AddCheckbox('x30 y+m+10', 'Show confidence % in recognition tooltip')
    objChkshowConfidence.Value := blnShowConfidence
    goo.AddButton('x+m yp w150 h30', 'Test Recognition').OnEvent('Click', TestMicRecognition)
    objTxtTestResult := goo.AddText('x+m yp h40', "Click 'Test Recognition' and speak...")

    goo.AddButton('x30 y+m+30 h30', 'Save Microphone Settings').OnEvent('Click', SaveMicSettings)

    tab.UseTab(0)											; close construction context
    tab.Value := defaultTab									; select correct tab
    SetTimer(UpdateAudioLevel, defaultTab = 3 ? 100 : 0)	; start monitor if Mic tab
    goo.Show('AutoSize Center')
}

UpdateHotkey(cb, edt, token, type) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
	oldHotkey := IniRead(strIniFile, 'HotKeys', type)

	newHotkey := oldHotkey
	alreadyIn := InStr(edt.Value, token)
	if (cb.Value) && !alreadyIn
		edt.Value := token . edt.Value
	else if !cb.Value && alreadyIn
		edt.Value := StrReplace(edt.Value, token, '')

    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 2)
}

/** @description HotkeyCmdMicGuiClose - Close handler: stop audio monitor and destroy GUI */
HotkeyCmdMicGuiClose(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global goo
    SetTimer(UpdateAudioLevel, 0)
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

;============================================================
; START OF MICROPHONE SETTINGS IN HotkeyCmdMicGui
;============================================================

; Threshold Slider Change Event
ThresholdSliderChange(ctrl, *) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objTxtThresholdValue
    objTxtThresholdValue.Text := ctrl.Value "%"
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
    global objSliderThreshold, objChkshowConfidence
    global fltConfidenceThreshold, blnShowConfidence

    try {
        IniWrite(strCurrentMicName, strIniFile, "Settings", "microphoneName")

        ; Save confidence settings
        intThreshold := objSliderThreshold.Value
        fltConfidenceThreshold := intThreshold / 100
        blnShowConfidence := objChkshowConfidence.Value

        IniWrite(intThreshold, strIniFile, "Settings", "confidenceThreshold")
        IniWrite(blnShowConfidence ? "1" : "0", strIniFile, "Settings", "showConfidence")

        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Saved mic: [" intCurrentMicIndex "] " strCurrentMicName, 2)
        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Saved threshold: " intThreshold "%, ShowConf: " blnShowConfidence, 2)

        MsgBox("Microphone settings saved!`n`nMicrophone: " strCurrentMicName "`nConfidence Threshold: " intThreshold "%", "Settings Saved", "Iconi")
    } catch as err {
        LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . "Failed to save: " err.Message, 4)
        MsgBox("Failed to save settings: " err.Message, "Error", "Icon!")
    }
}

; Test Microphone Recognition
TestMicRecognition(*) {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objTxtTestResult, blnMicTestMode

    objTxtTestResult.Text := "Listening... Speak now!"
    blnMicTestMode := true

    ; Set a timeout to reset
    SetTimer(ResetMicTest, -5000)
}

; Reset Microphone Test
ResetMicTest() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objTxtTestResult, blnMicTestMode

    if (blnMicTestMode) {
        blnMicTestMode := false
        if (objTxtTestResult != "") {
            try {
                objTxtTestResult.Text := "No speech detected. Try again or check microphone."
            }
        }
    }
}

;============================================================
; END OF MICROPHONE SETTINGS IN HotkeyCmdMicGui
;============================================================

;============================================================
; AUDIO LEVEL MONITORING
;============================================================

; Update Audio Level Display
UpdateAudioLevel() {
    LogMsg(FFL('VC_UI', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objProgressLevel, objTxtLevelPercent, objRecognizer

    if (objProgressLevel = "" || objTxtLevelPercent = "") {
        return
    }

    try {
        ; Get audio level from recognizer status
        objStatus := objRecognizer.Status
        intLevel := objStatus.AudioStatus.AudioLevel

        ; AudioLevel is 0-100
        intPercent := Min(100, Max(0, intLevel))

        objProgressLevel.Value := intPercent
        objTxtLevelPercent.Text := "Level: " intPercent "%"
    } catch {
        ; Ignore errors during level monitoring
    }
}

;================= End of VC_UI.ahk =================
