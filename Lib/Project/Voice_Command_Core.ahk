;================= VC_Core.ahk =================
; SAPI Voice Recognition Engine voor Voice Command
; Bevat: Initialization, Grammar Building, Event Handling, Command Execution
;===============================================

;============================================================
; INITIALIZATION
;============================================================

/** @description InitializeVoiceRecognition - Set up SAPI voice recognition with TWO grammars
    @details - Creates main grammar for user commands
             - Creates control grammar for start/stop (always active) */
InitializeVoiceRecognition() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objRecognizer, objContext, objGrammar, objControlGrammar, objEventSink
    global mapCommands, mapBuiltInCommands, mapControlCommands, intTestMode, blnLogEnabled, blnListening, blnCommandsEnabled
    global intCurrentMicIndex, strCurrentMicName
    global fltConfidenceThreshold, blnShowConfidence
    global strLangId, strIniFile, objMicSettingsGui

    try {
        if !FileExist(strIniFile) {
            CreateDefaultIni()
        }

        strLogSetting := IniRead(strIniFile, "Settings", "logEnabled", "1")

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "=== Voice Command Starting (Option A: Dual Grammar) ===", 2)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "logEnabled: " (blnLogEnabled ? "ON" : "OFF"), 2)

        ; Load confidence settings
        LoadConfidenceSettings()

        mapCommands := LoadCommandsFromIni()

        intTestMode := Integer(IniRead(strIniFile, "Settings", "testMode", "0"))
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Test Mode: " (intTestMode ? "ON" : "OFF"), 2)

        if (!intTestMode && mapCommands.Count < 1) {
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "No commands found")
            MsgBox("No commands found in INI file.", "Error", "Icon!")
            ExitApp()
        }

        objRecognizer := ComObject("SAPI.SpInprocRecognizer")
        ; Dynamic SAPI language detection
        objToken := objRecognizer.Recognizer
        strLangId := objToken.GetAttribute("Language")
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'strLangId = ' strLangId, 2)

        objAudioInputs := objRecognizer.GetAudioInputs()
        intMicCount := objAudioInputs.Count

        if (intMicCount < 1) {
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "No microphones found!", 4)
            MsgBox("No audio input devices found!", "Error", "Icon!")
            ExitApp()
        }

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "=== Available Microphones ===", 2)
        Loop intMicCount {
            intIdx := A_Index - 1
            strMicName := objAudioInputs.Item(intIdx).GetDescription()
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "  [" intIdx "] " strMicName, 2)
        }
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "=============================", 2)

        ; Verify saved microphone or prompt for selection
        strVerifyResult := VerifyMicrophone()

        if (strVerifyResult = "SHOW_GUI") {
            intCurrentMicIndex := 0
            strCurrentMicName := objAudioInputs.Item(0).GetDescription()
            objRecognizer.AudioInput := objAudioInputs.Item(0)

            ShowMicrophoneSettingsGui(true)

            ; Wait for user to save microphone selection
            while (objMicSettingsGui != "" && WinExist("ahk_id " objMicSettingsGui.Hwnd)) {
                Sleep(100)
            }
        }

        objRecognizer.AudioInput := objAudioInputs.Item(intCurrentMicIndex)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Using mic [" intCurrentMicIndex "]: " strCurrentMicName, 2)

        objContext := objRecognizer.CreateRecoContext()

        objEventSink := VoiceEventSink()
        ComObjConnect(objContext, objEventSink)

        ; Create TWO grammars
        objGrammar := objContext.CreateGrammar(1)        ; Main grammar (ID=1)
        objControlGrammar := objContext.CreateGrammar(2) ; Control grammar (ID=2)

        if (intTestMode) {
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Loading DICTATION grammar", 2)
            objGrammar.DictationLoad()
            objGrammar.DictationSetState(1)

            MsgBox("DICTATION TEST MODE`n`nMicrophone: " strCurrentMicName, "Test Mode", "Iconi")
        } else {
            ; Build and load MAIN grammar (user commands + built-in)
            strMainGrammarFile := A_Temp "\voice_grammar_main.xml"
            BuildGrammarFile(mapCommands, mapBuiltInCommands, strMainGrammarFile)
            objGrammar.CmdLoadFromFile(strMainGrammarFile, 0)

            ; Build and load CONTROL grammar (start/stop only)
            strControlGrammarFile := A_Temp "\voice_grammar_control.xml"
            BuildControlGrammarFile(strControlGrammarFile)
            objControlGrammar.CmdLoadFromFile(strControlGrammarFile, 0)

            ; Enable both grammars initially
            objGrammar.CmdSetRuleState("cmd", 1)
            objControlGrammar.CmdSetRuleState("control", 1)

            blnListening := true
            blnCommandsEnabled := true
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Listening: ON, Commands: ENABLED", 2)

            UpdateTrayIcon()

            intTotalCmds := mapCommands.Count + mapBuiltInCommands.Count
            intThresholdPct := Round(fltConfidenceThreshold * 100)

            MsgBox("Voice command listener active (Option A: Dual Grammar).`n`nMicrophone: " strCurrentMicName "`nConfidence Threshold: " intThresholdPct "%`nLogging: " (blnLogEnabled ? "ON" : "OFF") "`nCommands: " intTotalCmds "`n`nSay 'Stop' to pause commands.`nSay 'Start' to resume commands.`nPress F1 to toggle listening ON/OFF.`nSay 'list commands' to see all commands.`nRight-click tray icon for menu.", "Voice Command Ready", "Iconi")
        }

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Voice command listener started", 2)

    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Failed to initialize: " err.Message, 4)
        MsgBox("Failed to initialize:`n`n" err.Message, "Error", "Icon!")
        ExitApp()
    }
}

/** @description VerifyMicrophone - Verify Saved Microphone Still Exists */
VerifyMicrophone() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . '=== Verifying Microphone ===', 1)
    global strIniFile, objRecognizer, intCurrentMicIndex, strCurrentMicName

    ; Read saved settings
    intSavedIndex := Integer(IniRead(strIniFile, "Settings", "microphoneIndex", "-1"))
    strSavedName := IniRead(strIniFile, "Settings", "microphoneName", "")

    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Saved Index: " intSavedIndex ", Saved Name: " strSavedName, 2)

    ; If no microphone configured, show GUI
    if (intSavedIndex < 0 || strSavedName = "") {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "No microphone configured", 2)
        return "SHOW_GUI"
    }

    ; Check if saved microphone still exists
    try {
        objAudioInputs := objRecognizer.GetAudioInputs()

        ; First try exact index match
        if (intSavedIndex < objAudioInputs.Count) {
            strCurrentName := objAudioInputs.Item(intSavedIndex).GetDescription()
            if (strCurrentName = strSavedName) {
                intCurrentMicIndex := intSavedIndex
                strCurrentMicName := strSavedName
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Verified: [" intSavedIndex "] " strSavedName, 2)
                return "OK"
            }
        }

        ; Index changed - search by name
        Loop objAudioInputs.Count {
            intIdx := A_Index - 1
            strName := objAudioInputs.Item(intIdx).GetDescription()
            if (strName = strSavedName) {
                intCurrentMicIndex := intIdx
                strCurrentMicName := strSavedName
                ; Update saved index
                IniWrite(intIdx, strIniFile, "Settings", "microphoneIndex")
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Found at new index: [" intIdx "] " strSavedName, 2)
                return "OK"
            }
        }

        ; Microphone not found
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Saved microphone not found: " strSavedName, 2)
        MsgBox("Previously configured microphone not found:`n" strSavedName "`n`nPlease select a new microphone.", "Microphone Missing", "Icon!")
        return "SHOW_GUI"

    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Verification error: " err.Message, 4)
        return "SHOW_GUI"
    }
}

;============================================================
; GRAMMAR BUILDING
;============================================================

/** @description BuildGrammarFile - Create SAPI grammar XML file from loaded commands */
BuildGrammarFile(mapUserCmds, mapBuiltIn, strFilePath) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strLangId

    if FileExist(strFilePath) {
        FileDelete(strFilePath)
    }

    strXml := '<?xml version="1.0" encoding="ISO-8859-1"?>'
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'strLangId = ' strLangId, 2)
    strXml .= '<GRAMMAR LANGID="' . strLangId . '">'
    strXml .= '<RULE NAME="cmd" ID="1" TOPLEVEL="ACTIVE">'
    strXml .= '<L>'

    for strPhrase, strAction in mapBuiltIn {
        strXml .= "<P>" strPhrase "</P>"
    }

    for strPhrase, strAction in mapUserCmds {
        strXml .= "<P>" strPhrase "</P>"
    }

    strXml .= "</L>"
    strXml .= "</RULE>"
    strXml .= "</GRAMMAR>"

    objFile := FileOpen(strFilePath, "w", "CP0")
    objFile.Write(strXml)
    objFile.Close()

    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Grammar built with " (mapBuiltIn.Count + mapUserCmds.Count) " commands", 2)
}

/** @description BuildControlGrammarFile - Create grammar XML for control commands only (start/stop)
    @param {string} strFilePath - Path to write the XML grammar file
    @details - This grammar is ALWAYS active */
BuildControlGrammarFile(strFilePath) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strLangId, mapControlCommands

    if FileExist(strFilePath) {
        FileDelete(strFilePath)
    }

    strXml := '<?xml version="1.0" encoding="ISO-8859-1"?>'
    strXml .= '<GRAMMAR LANGID="' . strLangId . '">'
    strXml .= '<RULE NAME="control" ID="2" TOPLEVEL="ACTIVE">'
    strXml .= '<L>'

    for strPhrase, strAction in mapControlCommands {
        strXml .= "<P>" strPhrase "</P>"
    }

    strXml .= "</L>"
    strXml .= "</RULE>"
    strXml .= "</GRAMMAR>"

    objFile := FileOpen(strFilePath, "w", "CP0")
    objFile.Write(strXml)
    objFile.Close()

    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Control grammar built with " mapControlCommands.Count " commands", 2)
}

/** @description RebuildGrammar - Rebuild Grammar After Command Changes */
RebuildGrammar() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objGrammar, mapCommands, mapBuiltInCommands, blnListening, blnCommandsEnabled

    try {
        ; Disable grammar during rebuild
        objGrammar.CmdSetRuleState("cmd", 0)

        ; Build new grammar file
        strTempFile := A_Temp "\voice_grammar.xml"
        BuildGrammarFile(mapCommands, mapBuiltInCommands, strTempFile)

        ; Reload grammar
        objGrammar.CmdLoadFromFile(strTempFile, 0)

        ; Re-enable if listening and commands enabled
        if (blnListening && blnCommandsEnabled) {
            objGrammar.CmdSetRuleState("cmd", 1)
        }

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Grammar rebuilt successfully", 2)

    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Grammar rebuild failed: " err.Message, 4)
    }
}

;============================================================
; VOICE EVENT HANDLING
;============================================================

class VoiceEventSink {

    __Call(strMethod, args) {
        if (strMethod != "Interference") {
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Event: " strMethod " (" args.Length " args)", 2)
        }

        if (strMethod = "Recognition") {
            this.HandleRecognition(args)
        }

        if (strMethod = "Hypothesis") {
            this.LogHypothesis(args)
        }

        if (strMethod = "FalseRecognition") {
            this.LogFalseRecognition(args)
        }

        return 0
    }

    /** @description HandleRecognition - Process successful voice recognition and filter by confidence */
    HandleRecognition(args) {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
        global intTestMode, fltConfidenceThreshold, blnShowConfidence, mapControlCommands

        for intIndex, arg in args {
            try {
                objPhraseInfo := arg.PhraseInfo
                if (objPhraseInfo) {
                    strText := objPhraseInfo.GetText()

                    ; Get confidence score
                    fltConfidence := 0.0
                    try {
                        ; Try to get confidence from the rule
                        fltConfidence := objPhraseInfo.Rule.EngineConfidence
                    } catch {
                        ; Fallback: try phrase elements
                        try {
                            fltConfidence := objPhraseInfo.Elements.Item(0).EngineConfidence
                        } catch {
                            fltConfidence := 1.0  ; Assume high confidence if can't retrieve
                        }
                    }

                    intConfPct := Round(fltConfidence * 100)
                    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "RECOGNIZED: " strText " (Confidence: " intConfPct "%)", 2)

                    ; Check against confidence threshold
                    if (fltConfidence < fltConfidenceThreshold) {
                        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "REJECTED: Below threshold (" Round(fltConfidenceThreshold * 100) "%)", 2)
                        ; Show rejection in tooltip
                        if (blnShowConfidence) {
                            ToolTip("❌ Rejected: " strText " (" intConfPct "% < " Round(fltConfidenceThreshold * 100) "%)")
                        } else {
                            ToolTip("❌ Rejected: Low confidence")
                        }
                        SetTimer(() => ToolTip(), -3000)
                        return
                    }

                    ; Show accepted recognition
                    if (blnShowConfidence) {
                        ToolTip("✓ Heard: " strText " (" intConfPct "%)")
                    } else {
                        ToolTip("Heard: " strText)
                    }
                    SetTimer(() => ToolTip(), -3000)

                    if (intTestMode) {
                        MsgBox("SAPI heard: " strText "`nConfidence: " intConfPct "%", "Dictation Test")
                    } else {
                        ; Check if this is a control command (start/stop)
                        strTextLower := StrLower(strText)
                        if (mapControlCommands.Has(strTextLower)) {
                            ControlHandler(strTextLower)
                        } else {
                            VoiceHandler(arg)
                        }
                    }
                    return
                }
            }
        }
    }

    /** @description LogHypothesis - Log intermediate hypothesis during voice recognition */
    LogHypothesis(args) {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
        for intIndex, arg in args {
            try {
                objPhraseInfo := arg.PhraseInfo
                if (objPhraseInfo) {
                    strText := objPhraseInfo.GetText()
                    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Hypothesis: " strText, 2)
                    return
                }
            }
        }
    }

    /** @description LogFalseRecognition - Log when SAPI thinks it heard something but rejects it */
    LogFalseRecognition(args) {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
        for intIndex, arg in args {
            try {
                objPhraseInfo := arg.PhraseInfo
                if (objPhraseInfo) {
                    strText := objPhraseInfo.GetText()
                    if (strText != "") {
                        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "FalseRecog: " strText, 2)
                    } else {
                        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "FalseRecog: (low confidence)", 2)
                    }
                    return
                }
            }
        }
    }
}

;============================================================
; COMMAND PROCESSING
;============================================================

/** @description ControlHandler - Handle control commands (start/stop) - always processed */
ControlHandler(strCommand) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started - Command: ' strCommand, 1)
    global objGrammar, blnCommandsEnabled, mapControlCommands

    strActionData := mapControlCommands[strCommand]
    arrayParts := StrSplit(strActionData, "|")
    strAction := StrLower(arrayParts[2])

    switch strAction {
        case "startcommands":
            if (!blnCommandsEnabled) {
                blnCommandsEnabled := true
                objGrammar.CmdSetRuleState("cmd", 1)
                ToolTip("▶️ Commands ACTIVE")
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Commands enabled via 'start'", 2)
                UpdateTrayIcon()
                SetTimer(() => ToolTip(), -2000)
            } else {
                ToolTip("ℹ️ Commands already active")
                SetTimer(() => ToolTip(), -2000)
            }

        case "stopcommands":
            if (blnCommandsEnabled) {
                blnCommandsEnabled := false
                objGrammar.CmdSetRuleState("cmd", 0)
                ToolTip("⏸️ Commands PAUSED (say 'Start' to resume)")
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Commands disabled via 'stop'", 2)
                UpdateTrayIcon()
                SetTimer(() => ToolTip(), -3000)
            } else {
                ToolTip("ℹ️ Commands already paused")
                SetTimer(() => ToolTip(), -2000)
            }
    }
}

/** @description VoiceHandler - Process voice recognition results and execute commands */
VoiceHandler(result) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapCommands, mapBuiltInCommands, blnCommandsEnabled

    try {
        strRecognizedText := StrLower(result.PhraseInfo.GetText())

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Processing: " strRecognizedText, 2)

        if (mapBuiltInCommands.Has(strRecognizedText)) {
            strActionData := mapBuiltInCommands[strRecognizedText]
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Built-in command: " strActionData, 2)
            ExecuteAction(strActionData)
            return
        }

        if (mapCommands.Has(strRecognizedText)) {
            strActionData := mapCommands[strRecognizedText]
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Executing: " strActionData, 2)
            ExecuteAction(strActionData)
        } else {
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Command not found: " strRecognizedText, 2)
        }

    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Error: " err.Message, 4)
    }
}

/** @description ExecuteAction - Perform the action associated with a recognized command */
ExecuteAction(strActionData) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objGrammar, blnListening

    arrayParts := StrSplit(strActionData, "|", , 3)

    if (arrayParts.Length = 3) {
        strAction := StrLower(Trim(arrayParts[2]))
        strTarget := Trim(arrayParts[3])
    } else if (arrayParts.Length = 2) {
        strAction := StrLower(Trim(arrayParts[1]))
        strTarget := Trim(arrayParts[2])
    } else {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Invalid action format: " strActionData, 2)
        return
    }

    switch strAction {
        case "run", "file":
            try {
                Run(strTarget)
            } catch as err {
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Run failed: " err.Message, 2)
            }

        case "winclose":
            try {
                WinClose(strTarget)
            } catch as err {
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "WinClose failed: " err.Message, 2)
            }

        case "send", "keypress":
            try {
                Send(strTarget)
            } catch as err {
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Send failed: " err.Message, 2)
            }

        case "mouse":
            ExecuteMouseAction(strTarget)

        case "msgbox":
            MsgBox(strTarget, "Voice Command")

        case "builtin":
            switch strTarget {
                case "listcommands":
                    ShowCommandList()
                case "stoplistening":
                    objGrammar.CmdSetRuleState("cmd", 0)
                    blnListening := false
                    UpdateTrayIcon()
                    ToolTip("🔇 Listening PAUSED")
                    SetTimer(() => ToolTip(), -2000)
                    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Listening paused via voice", 2)
                case "startlistening":
                    objGrammar.CmdSetRuleState("cmd", 1)
                    blnListening := true
                    UpdateTrayIcon()
                    ToolTip("🎤 Listening RESUMED")
                    SetTimer(() => ToolTip(), -2000)
                    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Listening resumed via voice", 2)
            }

        case "function":
            try {
                %strTarget%()
            } catch as err {
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Function call failed: " err.Message, 2)
            }

        default:
            LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Unknown action: " strAction, 2)
    }
}

/** @description ExecuteMouseAction - Execute mouse-related voice commands */
ExecuteMouseAction(strTarget) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    strTargetLower := StrLower(strTarget)

    if (InStr(strTargetLower, "double click")) {
        strWindow := RegExReplace(strTarget, 'i)double\s*click\s*"?([^"]*)"?', "$1")
        strWindow := Trim(strWindow)

        if (strWindow != "") {
            try {
                if WinExist(strWindow) {
                    WinActivate(strWindow)
                    Sleep(100)
                    Click(2)
                    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Double-clicked: " strWindow, 2)
                } else {
                    Run(strWindow)
                    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Ran (not found as window): " strWindow, 2)
                }
            } catch as err {
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Mouse action failed: " err.Message, 2)
            }
        }
    } else if (InStr(strTargetLower, "click")) {
        strWindow := RegExReplace(strTarget, 'i)click\s*"?([^"]*)"?', "$1")
        strWindow := Trim(strWindow)

        if (strWindow != "") {
            try {
                if WinExist(strWindow) {
                    WinActivate(strWindow)
                    Sleep(100)
                    Click()
                    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Clicked: " strWindow, 2)
                }
            } catch as err {
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Mouse action failed: " err.Message, 2)
            }
        }
    } else {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Unknown mouse action: " strTarget, 4)
    }
}

/** @description ShowCommandList - Display a message box listing all available commands */
ShowCommandList() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapCommands, mapBuiltInCommands, mapControlCommands

    strList := "=== CONTROL COMMANDS (always active) ===`n"
    for strPhrase, strAction in mapControlCommands {
        strList .= "`u{2022} " strPhrase "`n"
    }

    strList .= "`n=== BUILT-IN COMMANDS ===`n"
    for strPhrase, strAction in mapBuiltInCommands {
        strList .= "`u{2022} " strPhrase "`n"
    }

    strList .= "`n=== USER COMMANDS ===`n"
    for strPhrase, strAction in mapCommands {
        arrayParts := StrSplit(strAction, "|", , 3)
        if (arrayParts.Length >= 2) {
            strType := arrayParts.Length = 3 ? arrayParts[2] : arrayParts[1]
        } else {
            strType := "?"
        }
        strList .= "`u{2022} " strPhrase " [" strType "]`n"
    }

    strList .= "`nTotal: " mapCommands.Count " user commands"

    MsgBox(strList, "Voice Commands", "Iconi")
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Listed commands", 2)
}

;================= End of VC_Core.ahk =================
