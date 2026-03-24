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
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objRecognizer, objContext, objGrammar, objControlGrammar, objEventSink
    global mapCommands, mapBuiltInCommands, mapControlCommands, blnLogEnabled, blnListening
    global intCurrentMicIndex, strCurrentMicName
    global fltConfidenceThreshold, blnShowConfidence
    global strLangId, strIniFile, objManagerTab

    try {
        if !FileExist(strIniFile) {
            CreateDefaultIni()
        }

        strLogSetting := IniRead(strIniFile, "Settings", "logEnabled", "1")

        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "=== Voice Command Starting (Option A: Dual Grammar) ===", 2)
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "logEnabled: " (blnLogEnabled ? "ON" : "OFF"), 2)

        ; Load confidence settings
        LoadConfidenceSettings()

        ; Load SAPI speak mode (0=log only, 1=tooltip+log for Hypothesis/FalseRecognition)
        intSapiSpeakMode := Integer(IniRead(strIniFile, "Settings", "sapiSpeakMode", "0"))

        mapCommands := LoadCommandsFromIni()

        if (mapCommands.Count < 1) {
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "No commands found")
            MsgBox("No commands found in INI file.", "Error", "Icon!")
            ExitApp()
        }

        objRecognizer := ComObject("SAPI.SpInprocRecognizer")
        ; Dynamic SAPI language detection
        objToken := objRecognizer.Recognizer
        strLangId := objToken.GetAttribute("Language")
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'strLangId = ' strLangId, 2)

        objAudioInputs := objRecognizer.GetAudioInputs()
        intMicCount := objAudioInputs.Count

        if (intMicCount < 1) {
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "No microphones found!", 4)
            MsgBox("No audio input devices found!", "Error", "Icon!")
            ExitApp()
        }

        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "=== Available Microphones ===", 2)
        Loop intMicCount {
            intIdx := A_Index - 1
            strMicName := objAudioInputs.Item(intIdx).GetDescription()
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "  [" intIdx "] " strMicName, 2)
        }
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "=============================", 2)

        ; Verify saved microphone or prompt for selection
        strVerifyResult := VerifyMicrophone()

        if (strVerifyResult = "SHOW_GUI") {
            intCurrentMicIndex := 0
            strCurrentMicName := objAudioInputs.Item(0).GetDescription()
            objRecognizer.AudioInput := objAudioInputs.Item(0)

            HotkeyCmdMicGui(3)
        }

        objRecognizer.AudioInput := objAudioInputs.Item(intCurrentMicIndex)
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Using mic [" intCurrentMicIndex "]: " strCurrentMicName, 2)

        objContext := objRecognizer.CreateRecoContext()

        objEventSink := VoiceEventSink()
        ComObjConnect(objContext, objEventSink)

        ; Create TWO grammars
        objGrammar := objContext.CreateGrammar(1)        ; Main grammar (ID=1)
        objControlGrammar := objContext.CreateGrammar(2) ; Control grammar (ID=2)

        ; Build and load MAIN grammar (user commands + built-in)
        strMainGrammarFile := A_Temp "\voice_grammar_main.xml"
        BuildGrammarFile(mapCommands, mapBuiltInCommands, strMainGrammarFile)
        objGrammar.CmdLoadFromFile(strMainGrammarFile, 0)

        ; Build and load CONTROL grammar (only when there are control commands)
        if (mapControlCommands.Count > 0) {
            strControlGrammarFile := A_Temp "\voice_grammar_control.xml"
            BuildControlGrammarFile(strControlGrammarFile)
            objControlGrammar.CmdLoadFromFile(strControlGrammarFile, 0)
            objControlGrammar.CmdSetRuleState("control", 1)
        }

        ; Enable main grammar
        objGrammar.CmdSetRuleState("cmd", 1)

        blnListening := true
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Listening: ON", 2)

        UpdateTrayIcon()

        intTotalCmds := mapCommands.Count + mapBuiltInCommands.Count
        intThresholdPct := Round(fltConfidenceThreshold * 100)

        MsgBox("Voice command listener active.`n`nMicrophone: " strCurrentMicName "`nConfidence Threshold: " intThresholdPct "%`nLogging: " (blnLogEnabled ? "ON" : "OFF") "`nCommands: " intTotalCmds "`n`nPress F1 to toggle listening ON/OFF.`nSay 'list commands' to see all commands.`nRight-click tray icon for menu.", "Voice Command Ready", "Iconi")

        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Voice command listener started", 2)

    } catch as err {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Failed to initialize: " err.Message, 4)
        MsgBox("Failed to initialize:`n`n" err.Message, "Error", "Icon!")
        ExitApp()
    }
}

/** @description VerifyMicrophone - Verify Saved Microphone Still Exists */
VerifyMicrophone() {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . '=== Verifying Microphone ===', 1)
    global strIniFile, objRecognizer, intCurrentMicIndex, strCurrentMicName

    ; Read saved microphone name
    strSavedName := IniRead(strIniFile, "Settings", "microphoneName", "")

    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Saved Name: " strSavedName, 2)

    ; If no microphone configured, show GUI
    if (strSavedName = "") {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "No microphone configured", 2)
        return "SHOW_GUI"
    }

    ; Search for saved microphone by name
    try {
        objAudioInputs := objRecognizer.GetAudioInputs()

        Loop objAudioInputs.Count {
            intIdx := A_Index - 1
            strName := objAudioInputs.Item(intIdx).GetDescription()
            if (strName = strSavedName) {
                intCurrentMicIndex := intIdx
                strCurrentMicName := strSavedName
                LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Found: [" intIdx "] " strSavedName, 2)
                return "OK"
            }
        }

        ; Microphone not found
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Saved microphone not found: " strSavedName, 2)
        MsgBox("Previously configured microphone not found:`n" strSavedName "`n`nPlease select a new microphone.", "Microphone Missing", "Icon!")
        return "SHOW_GUI"

    } catch as err {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Verification error: " err.Message, 4)
        return "SHOW_GUI"
    }
}

;============================================================
; GRAMMAR BUILDING
;============================================================

/** @description BuildGrammarFile - Create SAPI grammar XML file from loaded commands */
BuildGrammarFile(mapUserCmds, mapBuiltIn, strFilePath) {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strLangId

    if FileExist(strFilePath) {
        FileDelete(strFilePath)
    }

    strXml := '<?xml version="1.0" encoding="ISO-8859-1"?>'
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'strLangId = ' strLangId, 2)
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

    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Grammar built with " (mapBuiltIn.Count + mapUserCmds.Count) " commands", 2)
}

/** @description BuildControlGrammarFile - Create grammar XML for control commands only (start/stop)
    @param {string} strFilePath - Path to write the XML grammar file
    @details - This grammar is ALWAYS active */
BuildControlGrammarFile(strFilePath) {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
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

    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Control grammar built with " mapControlCommands.Count " commands", 2)
}

/** @description RebuildGrammar - Rebuild Grammar After Command Changes */
RebuildGrammar() {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objGrammar, mapCommands, mapBuiltInCommands, blnListening

    try {
        ; Disable grammar during rebuild
        objGrammar.CmdSetRuleState("cmd", 0)

        ; Build new grammar file
        strTempFile := A_Temp "\voice_grammar.xml"
        BuildGrammarFile(mapCommands, mapBuiltInCommands, strTempFile)

        ; Reload grammar
        objGrammar.CmdLoadFromFile(strTempFile, 0)

        ; Re-enable if listening
        if (blnListening) {
            objGrammar.CmdSetRuleState("cmd", 1)
        }

        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Grammar rebuilt successfully", 2)

    } catch as err {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Grammar rebuild failed: " err.Message, 4)
    }
}

;============================================================
; VOICE EVENT HANDLING
;============================================================

class VoiceEventSink {

    __Call(strMethod, args) {
        if (strMethod != "Interference") {
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Event: " strMethod " (" args.Length " args)", 2)
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
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
        global fltConfidenceThreshold, blnShowConfidence
        global fltIniThreshold, intAdaptN, fltAdaptSum, strIniFile

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

                    ; ── Adaptive threshold update ──────────────────────────────
                    intAdaptN   += 1
                    fltAdaptSum += fltConfidence
                    fltConfidenceThreshold := (10 * fltIniThreshold + fltAdaptSum) / (intAdaptN + 10)

                    if (Mod(intAdaptN, 10) = 0) {
                        intNewPct := Round(fltConfidenceThreshold * 100)
                        if (intNewPct != Round(fltIniThreshold * 100)) {
                            IniWrite(intNewPct, strIniFile, "Settings", "confidenceThreshold")
                            fltIniThreshold := fltConfidenceThreshold   ; new anchor
                        }
                        intAdaptN   := 0
                        fltAdaptSum := 0.0
                    }
                    ; ── End adaptive update ─────────────────────────────────────

                    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "RECOGNIZED: " strText " (Confidence: " intConfPct "%)", 2)

                    ; Check against confidence threshold
                    if (fltConfidence < fltConfidenceThreshold) {
                        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "REJECTED: Below threshold (" Round(fltConfidenceThreshold * 100) "%)", 2)
                        ; Show rejection in tooltip
                        if (blnShowConfidence) {
                            pool.ShowByMouse('❌ Rejected: ' strText ' (' intConfPct '% < \' Round(fltConfidenceThreshold * 100) '%)', 3000)
                        } else {
                            pool.ShowByMouse('❌ Rejected: Low confidence', 3000)
                        }
                        return
                    }

                    ; Show accepted recognition
                    if (blnShowConfidence) {
                        pool.ShowByMouse('✓ Heard: ' strText ' (' intConfPct '%)', 3000)
                    } else {
                        pool.ShowByMouse('Heard: ' strText, 3000)
                    }

                    VoiceHandler(arg)
                    return
                }
            }
        }
    }

    /** @description LogHypothesis - Log intermediate hypothesis during voice recognition */
    LogHypothesis(args) {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
        global intSapiSpeakMode
        for intIndex, arg in args {
            try {
                objPhraseInfo := arg.PhraseInfo
                if (objPhraseInfo) {
                    strText := objPhraseInfo.GetText()
                    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Hypothesis: " strText, 2)
                    if (intSapiSpeakMode = 1) {
                        pool.ShowByMouse('? Hypothesis: ' strText, 3000)
                    }
                    return
                }
            }
        }
    }

    /** @description LogFalseRecognition - Log when SAPI thinks it heard something but rejects it */
    LogFalseRecognition(args) {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
        global intSapiSpeakMode
        for intIndex, arg in args {
            try {
                objPhraseInfo := arg.PhraseInfo
                if (objPhraseInfo) {
                    strText := objPhraseInfo.GetText()
                    if (strText != "") {
                        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "FalseRecog: " strText, 2)
                        if (intSapiSpeakMode = 1) {
                            pool.ShowByMouse('~ False: ' strText, 3000)
                        }
                    } else {
                        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "FalseRecog: (low confidence)", 2)
                        if (intSapiSpeakMode = 1) {
                            pool.ShowByMouse('~ False: (low confidence)', 3000)
                        }
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

/** @description VoiceHandler - Process voice recognition results and execute commands */
VoiceHandler(result) {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapCommands, mapBuiltInCommands

    try {
        strRecognizedText := StrLower(result.PhraseInfo.GetText())

        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Processing: " strRecognizedText, 2)

        if (mapBuiltInCommands.Has(strRecognizedText)) {
            strActionData := mapBuiltInCommands[strRecognizedText]
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Built-in command: " strActionData, 2)
            ExecuteAction(strActionData)
            return
        }

        if (mapCommands.Has(strRecognizedText)) {
            strActionData := mapCommands[strRecognizedText]
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Executing: " strActionData, 2)
            ExecuteAction(strActionData)
        } else {
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Command not found: " strRecognizedText, 2)
        }

    } catch as err {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Error: " err.Message, 4)
    }
}

/** @description ExecuteAction - Perform the action associated with a recognized command */
ExecuteAction(strActionData) {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objGrammar, blnListening

    arrayParts := StrSplit(strActionData, "|", , 2)

    if (arrayParts.Length = 2) {
        strAction := StrLower(Trim(arrayParts[1]))
        strTarget := Trim(arrayParts[2])
    } else {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Invalid action format: " strActionData, 2)
        return
    }

    switch strAction {
        case "run", "file":
            try {
                Run(strTarget)
            } catch as err {
                LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Run failed: " err.Message, 2)
            }

        case "winclose":
            try {
                WinClose(strTarget)
            } catch as err {
                LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "WinClose failed: " err.Message, 2)
            }

        case "send", "keypress":
            try {
                Send(strTarget)
            } catch as err {
                LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Send failed: " err.Message, 2)
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
                    pool.ShowByMouse('🔇 Listening PAUSED', 2000)
                    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Listening paused via voice", 2)
                case "startlistening":
                    objGrammar.CmdSetRuleState("cmd", 1)
                    blnListening := true
                    UpdateTrayIcon()
                    pool.ShowByMouse('🎤 Listening RESUMED', 2000)
                    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Listening resumed via voice", 2)
            }

        case "function":
            try {
                %strTarget%()
            } catch as err {
                LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Function call failed: " err.Message, 2)
            }

        default:
            LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Unknown action: " strAction, 2)
    }
}

/** @description ExecuteMouseAction - Execute mouse-related voice commands */
ExecuteMouseAction(strTarget) {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
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
                    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Double-clicked: " strWindow, 2)
                } else {
                    Run(strWindow)
                    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Ran (not found as window): " strWindow, 2)
                }
            } catch as err {
                LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Mouse action failed: " err.Message, 2)
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
                    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Clicked: " strWindow, 2)
                }
            } catch as err {
                LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Mouse action failed: " err.Message, 2)
            }
        }
    } else {
        LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Unknown mouse action: " strTarget, 4)
    }
}

/** @description ShowCommandList - Display a message box listing all available commands */
ShowCommandList() {
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapCommands, mapBuiltInCommands

    strList := "=== BUILT-IN COMMANDS ===`n"
    for strPhrase, strAction in mapBuiltInCommands {
        strList .= "`u{2022} " strPhrase "`n"
    }

    strList .= "`n=== USER COMMANDS ===`n"
    for strPhrase, strAction in mapCommands {
        arrayParts := StrSplit(strAction, "|", , 2)
        if (arrayParts.Length >= 2) {
            strType := arrayParts[1]
        } else {
            strType := "?"
        }
        strList .= "`u{2022} " strPhrase " [" strType "]`n"
    }

    strList .= "`nTotal: " mapCommands.Count " user commands"

    MsgBox(strList, "Voice Commands", "Iconi")
    LogMsg(FFL('VC_Core', A_ThisFunc, A_LineNumber) . "Listed commands", 2)
}

;================= End of VC_Core.ahk =================
