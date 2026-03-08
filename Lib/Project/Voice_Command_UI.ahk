;================= VC_UI.ahk =================
; User Interface & Visuals voor Voice Command
; Bevat: Tray Menu, Status Circle, Command Manager GUI, Microphone Settings GUI
;=============================================

;============================================================
; TRAY MENU
;============================================================

/** @description SetupTrayMenu - Build the system tray context menu */
SetupTrayMenu() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Command Manager", ShowCommandManagerMenu)
    A_TrayMenu.Add("Microphone Settings", ShowMicSettingsMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reload Commands", ReloadCommandsMenu)
    A_TrayMenu.Add("Edit INI File", EditIniMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Toggle Listening (F1)", ToggleListeningMenu)
    A_TrayMenu.Add("Toggle Logging", ToggleLoggingMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", ExitMenu)

    A_TrayMenu.Default := "Command Manager"
}

; Tray Menu Callbacks
ShowCommandManagerMenu(*) {
    ShowCommandManagerGui()
}

ShowMicSettingsMenu(*) {
    ShowMicrophoneSettingsGui()
}

ReloadCommandsMenu(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapCommands

    mapCommands := LoadCommandsFromIni()
    RebuildGrammar()

    MsgBox("Commands reloaded: " mapCommands.Count " commands", "Reload Complete", "Iconi")
}

EditIniMenu(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
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
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global blnLogEnabled, strIniFile

    blnLogEnabled := !blnLogEnabled

    try {
        IniWrite(blnLogEnabled ? "1" : "0", strIniFile, "Settings", "logEnabled")
    }

    MsgBox("Logging is now " (blnLogEnabled ? "ON" : "OFF"), "Logging Toggle", "Iconi")
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Logging toggled: " (blnLogEnabled ? "ON" : "OFF"), 2)
}

ExitMenu(*) {
    static blnExiting := false
    if (blnExiting)
        return
    blnExiting := true
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    CleanupVoice('User Exit', 0)
}

;============================================================
; TRAY ICON & TOGGLE LISTENING
;============================================================

/** @description UpdateTrayIcon - Update tray icon and status circle based on listening state */
UpdateTrayIcon() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global blnListening, blnCommandsEnabled
    global strIconListening, intIconListeningNum
    global strIconNotListening, intIconNotListeningNum

    if (blnListening) {
        if (blnCommandsEnabled) {
            TraySetIcon(strIconListening, intIconListeningNum)
            A_IconTip := "Voice Command - Listening (Active)"
        } else {
            TraySetIcon(strIconListening, intIconListeningNum)
            A_IconTip := "Voice Command - Listening (Paused - say 'Start')"
        }
    } else {
        TraySetIcon(strIconNotListening, intIconNotListeningNum)
        A_IconTip := "Voice Command - NOT Listening"
    }

    UpdateStatusCircle()
}

/** @description ToggleListening - Toggle voice command listening state on/off */
ToggleListening() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objGrammar, objControlGrammar, blnListening, blnCommandsEnabled, intTestMode

    if (intTestMode) {
        ToolTip("Cannot toggle in Test Mode")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    blnListening := !blnListening

    if (blnListening) {
        ; Enable control grammar (always)
        objControlGrammar.CmdSetRuleState("control", 1)
        ; Enable main grammar only if commands are enabled
        if (blnCommandsEnabled) {
            objGrammar.CmdSetRuleState("cmd", 1)
        }
        ToolTip("🎤 Listening ON")
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Listening toggled ON via F1", 2)
    } else {
        ; Disable both grammars
        objGrammar.CmdSetRuleState("cmd", 0)
        objControlGrammar.CmdSetRuleState("control", 0)
        ToolTip("🔇 Listening OFF")
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Listening toggled OFF via F1", 2)
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
    @details - strVoiceMode drives color: sapi=blue, vosk=green, whisper=purple, pause=orange
             - blnListening=false overrides to red regardless of mode */
GetStatusColor() {
    global blnListening, blnCommandsEnabled, strVoiceMode
    global strColorListening, strColorNotListening, strColorPaused, strColorVosk, strColorWhisper

    if (!blnListening)
        return strColorNotListening     ; Red — F1 listening OFF

    switch strVoiceMode {
        case "vosk":    return strColorVosk             ; Green
        case "whisper": return strColorWhisper          ; Purple
        case "pause":   return strColorPaused           ; Orange
        default:        return blnCommandsEnabled ? strColorListening : strColorPaused
    }
}

/** @description CreateStatusCircle - Create the visual status circle overlay window */
CreateStatusCircle() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objStatusCircle, intCircleSize, intCircleMargin

    ; Calculate position in upper right corner
    intXPos := A_ScreenWidth - intCircleMargin - (intCircleSize // 2)
    intYPos := intCircleMargin + (intCircleSize // 2)

    objStatusCircle := ShowCircle(intCircleSize, GetStatusColor(), intXPos, intYPos, GetStatusLabel())
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Status circle created at " intXPos ", " intYPos, 2)
}

/** @description UpdateStatusCircle - Update status circle color when listening state changes */
UpdateStatusCircle() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
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
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
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

/** @description ShowCommandManagerGui - Show the Command Manager GUI */
ShowCommandManagerGui() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objCmdManagerGui, objLvCommands
    global objEdtWordsSaid, objEdtGroup, objDdlType, objEdtAction
    global mapCommands, intSelectedRow
    global strIniFile

    intGuiHeight := Integer(IniRead(strIniFile, "Gui", "height", 40))
    intGuiWidth := Integer(IniRead(strIniFile, "Gui", "width", 1000))
    intGuiWidthCol4 := Integer(IniRead(strIniFile, "Gui", "width_col4", 600))
    intGuiWidthCol1 := (intGuiWidth - intGuiWidthCol4 - 40) // 3

    ; If GUI already exists, just show it
    if (objCmdManagerGui != "") {
        try {
            objCmdManagerGui.Show()
            return
        }
    }

    intSelectedRow := 0

    objCmdManagerGui := Gui("+Resize", "Voice Command Manager")
    objCmdManagerGui.SetFont("s10", "Segoe UI")
    objCmdManagerGui.OnEvent("Close", CmdManagerClose)

    ; Input Fields Row
    objCmdManagerGui.AddText("Section", "Words Said:")
    objCmdManagerGui.AddText("x+80", "Group:")
    objCmdManagerGui.AddText("x+80", "Type:")
    objCmdManagerGui.AddText("x+80", "Action:")

    objCmdManagerGui.AddText("xs", "")
    objEdtWordsSaid := objCmdManagerGui.AddEdit("xs w150")
    objEdtGroup := objCmdManagerGui.AddEdit("x+10 w100")
    objDdlType := objCmdManagerGui.AddDropDownList("x+10 w100", ["Run", "File", "WinClose", "Send", "Mouse", "MsgBox", "Function"])
    objEdtAction := objCmdManagerGui.AddEdit("x+10 w" intGuiWidthCol4)

    ; Action Buttons
    objCmdManagerGui.AddText("xs", "")
    objBtnAdd := objCmdManagerGui.AddButton("xs w80", "Add")
    objBtnAdd.OnEvent("Click", AddCommand)
    objBtnEdit := objCmdManagerGui.AddButton("x+10 w80", "Update")
    objBtnEdit.OnEvent("Click", EditCommand)
    objBtnDelete := objCmdManagerGui.AddButton("x+10 w80", "Delete")
    objBtnDelete.OnEvent("Click", DeleteCommand)
    objBtnClear := objCmdManagerGui.AddButton("x+10 w80", "Clear")
    objBtnClear.OnEvent("Click", ClearFields)

    ; Command ListView
    objCmdManagerGui.AddText("xs", "")
    strLvOptions := "xs w" intGuiWidth " h300 Grid LV0x20"
    objLvCommands := objCmdManagerGui.AddListView(strLvOptions, ["Words Said", "Group", "Type", "Action"])
    objLvCommands.OnEvent("Click", CommandListClick)
    objLvCommands.OnEvent("DoubleClick", CommandListDoubleClick)

    ; Populate ListView
    RefreshCommandList()

    ; Set column widths
    objLvCommands.ModifyCol(1, intGuiWidthCol1)
    objLvCommands.ModifyCol(2, intGuiWidthCol1)
    objLvCommands.ModifyCol(3, intGuiWidthCol1)
    objLvCommands.ModifyCol(4, intGuiWidthCol4)

    objCmdManagerGui.Show()
}

/** @description RefreshCommandList - Refresh Command List in ListView */
RefreshCommandList() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objLvCommands, mapCommands

    if (objLvCommands = "") {
        return
    }

    objLvCommands.Delete()

    for strPhrase, strActionData in mapCommands {
        arrayParts := StrSplit(strActionData, "|", , 3)

        if (arrayParts.Length = 3) {
            strGroup := arrayParts[1]
            strType := arrayParts[2]
            strAction := arrayParts[3]
        } else if (arrayParts.Length = 2) {
            strGroup := ""
            strType := arrayParts[1]
            strAction := arrayParts[2]
        } else {
            strGroup := ""
            strType := ""
            strAction := strActionData
        }

        objLvCommands.Add("", strPhrase, strGroup, strType, strAction)
    }
}

; Command List Click - Populate Fields
CommandListClick(ctrl, info) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objEdtWordsSaid, objEdtGroup, objDdlType, objEdtAction, intSelectedRow

    intSelectedRow := ctrl.GetNext(0, "Focused")
    if (intSelectedRow > 0) {
        strPhrase := ctrl.GetText(intSelectedRow, 1)
        strGroup := ctrl.GetText(intSelectedRow, 2)
        strType := ctrl.GetText(intSelectedRow, 3)
        strAction := ctrl.GetText(intSelectedRow, 4)

        objEdtWordsSaid.Value := strPhrase
        objEdtGroup.Value := strGroup
        objDdlType.Text := strType
        objEdtAction.Value := strAction
    }
}

; Command List Double-Click
CommandListDoubleClick(ctrl, info) {
    CommandListClick(ctrl, info)
}

; Add Command
AddCommand(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objEdtWordsSaid, objEdtGroup, objDdlType, objEdtAction
    global mapCommands, strIniFile

    strPhrase := Trim(objEdtWordsSaid.Value)
    strGroup := Trim(objEdtGroup.Value)
    strType := objDdlType.Text
    strAction := Trim(objEdtAction.Value)

    if (strPhrase = "" || strAction = "") {
        MsgBox("Please enter both 'Words Said' and 'Action'.", "Missing Input", "Icon!")
        return
    }

    strActionData := strGroup "|" strType "|" strAction
    mapCommands[StrLower(strPhrase)] := strActionData

    ; Save to INI
    IniWrite(strActionData, strIniFile, "Commands", strPhrase)

    RefreshCommandList()
    ClearFields()

    ; Rebuild grammar
    RebuildGrammar()

    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Added command: " strPhrase " => " strActionData, 2)
}

; Edit Command
EditCommand(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objEdtWordsSaid, objEdtGroup, objDdlType, objEdtAction
    global objLvCommands, mapCommands, strIniFile, intSelectedRow

    if (intSelectedRow < 1) {
        MsgBox("Please select a command to edit.", "No Selection", "Icon!")
        return
    }

    strOldPhrase := objLvCommands.GetText(intSelectedRow, 1)
    strPhrase := Trim(objEdtWordsSaid.Value)
    strGroup := Trim(objEdtGroup.Value)
    strType := objDdlType.Text
    strAction := Trim(objEdtAction.Value)

    if (strPhrase = "" || strAction = "") {
        MsgBox("Please enter both 'Words Said' and 'Action'.", "Missing Input", "Icon!")
        return
    }

    ; Remove old entry if phrase changed
    if (StrLower(strOldPhrase) != StrLower(strPhrase)) {
        mapCommands.Delete(StrLower(strOldPhrase))
        IniDelete(strIniFile, "Commands", strOldPhrase)
    }

    strActionData := strGroup "|" strType "|" strAction
    mapCommands[StrLower(strPhrase)] := strActionData

    ; Save to INI
    IniWrite(strActionData, strIniFile, "Commands", strPhrase)

    RefreshCommandList()
    ClearFields()

    ; Rebuild grammar
    RebuildGrammar()

    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Updated command: " strPhrase " => " strActionData, 2)
}

; Delete Command
DeleteCommand(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objLvCommands, mapCommands, strIniFile, intSelectedRow

    if (intSelectedRow < 1) {
        MsgBox("Please select a command to delete.", "No Selection", "Icon!")
        return
    }

    strPhrase := objLvCommands.GetText(intSelectedRow, 1)

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

    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Deleted command: " strPhrase, 2)
}

; Clear Input Fields
ClearFields(*) {
    global objEdtWordsSaid, objEdtGroup, objDdlType, objEdtAction, intSelectedRow

    objEdtWordsSaid.Value := ""
    objEdtGroup.Value := ""
    objDdlType.Choose(0)
    objEdtAction.Value := ""
    intSelectedRow := 0
}

; Close Command Manager
CmdManagerClose(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objCmdManagerGui

    if (objCmdManagerGui != "") {
        objCmdManagerGui.Destroy()
        objCmdManagerGui := ""
    }
}

;============================================================
; MICROPHONE SETTINGS GUI
;============================================================

/** @description ShowMicrophoneSettingsGui - Create and display microphone configuration interface */
ShowMicrophoneSettingsGui(blnForceSelection := false) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objMicSettingsGui, objLvMicrophones, objProgressLevel
    global objTxtLevelPercent, objTxtMicStatus, objTxtTestResult
    global objRecognizer, intCurrentMicIndex, strCurrentMicName
    global objSliderThreshold, objTxtThresholdValue, objChkshowConfidence
    global fltConfidenceThreshold, blnShowConfidence

    ; If GUI already exists, just show it
    if (objMicSettingsGui != "") {
        try {
            objMicSettingsGui.Show()
            return
        }
    }

    objMicSettingsGui := Gui("+Resize -MaximizeBox", "Microphone Settings")
    objMicSettingsGui.SetFont("s10", "Segoe UI")
    objMicSettingsGui.OnEvent("Close", MicSettingsClose)

    ; Instructions
    if (blnForceSelection) {
        objMicSettingsGui.AddText("w400", "No microphone configured. Please select your microphone:")
    } else {
        objMicSettingsGui.AddText("w400", "Select your microphone for voice recognition:")
    }

    ; Microphone list
    objLvMicrophones := objMicSettingsGui.AddListView("w400 h150 -Multi", ["#", "Microphone Name"])
    objLvMicrophones.OnEvent("Click", MicListClick)

    ; Populate microphone list
    try {
        objAudioInputs := objRecognizer.GetAudioInputs()
        Loop objAudioInputs.Count {
            intIdx := A_Index - 1
            strMicName := objAudioInputs.Item(intIdx).GetDescription()
            objLvMicrophones.Add("", intIdx, strMicName)

            ; Select current microphone
            if (intIdx = intCurrentMicIndex) {
                objLvMicrophones.Modify(A_Index, "+Select +Focus")
            }
        }
    }

    objLvMicrophones.ModifyCol(1, 30)
    objLvMicrophones.ModifyCol(2, 360)

    ; Current selection display
    objMicSettingsGui.AddText("w400", "")
    objTxtMicStatus := objMicSettingsGui.AddText("w400", "Current: " strCurrentMicName)

    ; Audio level meter section
    objMicSettingsGui.AddText("w400", "")
    objMicSettingsGui.AddText("w400", "Audio Level (speak to test):")
    objProgressLevel := objMicSettingsGui.AddProgress("w400 h20 Range0-100", 0)
    objTxtLevelPercent := objMicSettingsGui.AddText("w400", "Level: 0%")

    ; Confidence Threshold section
    objMicSettingsGui.AddText("w400", "")
    objMicSettingsGui.AddText("w400", "Confidence Threshold (reject below this %):")

    intCurrentThreshold := Round(fltConfidenceThreshold * 100)
    objSliderThreshold := objMicSettingsGui.AddSlider("w300 Range0-100 TickInterval10 AltSubmit", intCurrentThreshold)
    objSliderThreshold.OnEvent("Change", ThresholdSliderChange)
    objTxtThresholdValue := objMicSettingsGui.AddText("x+10 w50", intCurrentThreshold "%")

    objMicSettingsGui.AddText("xs w400", "")
    objChkshowConfidence := objMicSettingsGui.AddCheckbox("w400", "Show confidence % in recognition tooltip")
    objChkshowConfidence.Value := blnShowConfidence

    ; Test section
    objMicSettingsGui.AddText("w400", "")
    objMicSettingsGui.AddButton("w150", "Test Recognition").OnEvent("Click", TestMicRecognition)
    objTxtTestResult := objMicSettingsGui.AddText("w400 h40", "Click 'Test Recognition' and speak...")

    ; Buttons
    objMicSettingsGui.AddText("w400", "")
    objBtnSave := objMicSettingsGui.AddButton("w100", "Save")
    objBtnSave.OnEvent("Click", SaveMicSettings)

    if (!blnForceSelection) {
        objBtnCancel := objMicSettingsGui.AddButton("x+10 w100", "Cancel")
        objBtnCancel.OnEvent("Click", MicSettingsClose)
    }

    ; Start audio level monitoring
    StartAudioLevelMonitor()

    objMicSettingsGui.Show()
}

; Threshold Slider Change Event
ThresholdSliderChange(ctrl, *) {
    global objTxtThresholdValue
    objTxtThresholdValue.Text := ctrl.Value "%"
}

; Microphone List Click Event
MicListClick(ctrl, info) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
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
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Switched to mic: " strName, 2)
        } catch as err {
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Failed to switch mic: " err.Message, 4)
        }
    }
}

; Save Microphone Settings
SaveMicSettings(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile, intCurrentMicIndex, strCurrentMicName, objMicSettingsGui
    global objSliderThreshold, objChkshowConfidence
    global fltConfidenceThreshold, blnShowConfidence

    try {
        IniWrite(intCurrentMicIndex, strIniFile, "Settings", "microphoneIndex")
        IniWrite(strCurrentMicName, strIniFile, "Settings", "microphoneName")

        ; Save confidence settings
        intThreshold := objSliderThreshold.Value
        fltConfidenceThreshold := intThreshold / 100
        blnShowConfidence := objChkshowConfidence.Value

        IniWrite(intThreshold, strIniFile, "Settings", "confidenceThreshold")
        IniWrite(blnShowConfidence ? "1" : "0", strIniFile, "Settings", "showConfidence")

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Saved mic: [" intCurrentMicIndex "] " strCurrentMicName, 2)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Saved threshold: " intThreshold "%, ShowConf: " blnShowConfidence, 2)

        MsgBox("Microphone settings saved!`n`nMicrophone: " strCurrentMicName "`nConfidence Threshold: " intThreshold "%", "Settings Saved", "Iconi")
    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Failed to save: " err.Message, 4)
        MsgBox("Failed to save settings: " err.Message, "Error", "Icon!")
    }

    StopAudioLevelMonitor()
    objMicSettingsGui.Destroy()
    objMicSettingsGui := ""
}

; Close Microphone Settings
MicSettingsClose(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objMicSettingsGui

    StopAudioLevelMonitor()

    if (objMicSettingsGui != "") {
        objMicSettingsGui.Destroy()
        objMicSettingsGui := ""
    }
}

; Test Microphone Recognition
TestMicRecognition(*) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objTxtTestResult, blnMicTestMode

    objTxtTestResult.Text := "Listening... Speak now!"
    blnMicTestMode := true

    ; Set a timeout to reset
    SetTimer(ResetMicTest, -5000)
}

; Reset Microphone Test
ResetMicTest() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
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
; AUDIO LEVEL MONITORING
;============================================================

; Start Audio Level Monitor
StartAudioLevelMonitor() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    SetTimer(UpdateAudioLevel, 100)
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Audio Level Monitor Started", 2)
}

; Stop Audio Level Monitor
StopAudioLevelMonitor() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    SetTimer(UpdateAudioLevel, 0)
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Audio Level Monitor Stopped", 2)
}

; Update Audio Level Display
UpdateAudioLevel() {
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
