;================= VC_Utils.ahk =================
; Utilities & Helpers voor Voice Command
; Bevat: Logging, INI handling, Setup, Cleanup
;================================================

/** @description SetupBuiltInCommands - Setup built-in and control commands
    @details - Control commands (start/stop) go in separate grammar
             - Built-in commands in main grammar */
SetupBuiltInCommands() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapBuiltInCommands, mapControlCommands

    ; Control commands - these go in a SEPARATE grammar that's always active
    mapControlCommands["start"] := "control|startcommands"
    mapControlCommands["pause"] := "control|stopcommands"

    ; These commands are always available in main grammar
    mapBuiltInCommands["list commands"] := "builtin|listcommands"
    mapBuiltInCommands["show commands"] := "builtin|listcommands"
    mapBuiltInCommands["help"] := "builtin|listcommands"
    mapBuiltInCommands["stop listening"] := "builtin|stoplistening"
    mapBuiltInCommands["start listening"] := "builtin|startlistening"
}

/** @description CreateDefaultIni - Create default Voice_Command.ini file with sample commands
    @details - Creates INI file if it doesn't exist
             - Includes sample command entries for reference */
CreateDefaultIni() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile

    try {
        IniWrite("-1", strIniFile, "Settings", "microphoneIndex")
        IniWrite("", strIniFile, "Settings", "microphoneName")
        IniWrite("0", strIniFile, "Settings", "testMode")
        IniWrite("7", strIniFile, "Settings", "loggingType")
        IniWrite("40", strIniFile, "Settings", "confidenceThreshold")
        IniWrite("1", strIniFile, "Settings", "showConfidence")
        IniWrite("nl", strIniFile, "Settings", "localLanguage")
        IniWrite("EN", strIniFile, "Settings", "defaultLanguage")

        ; Sample commands
        IniWrite("General|MsgBox|Hello World!", strIniFile, "Commands", "hello")
        IniWrite("General|Run|notepad.exe", strIniFile, "Commands", "notepad")
        IniWrite("General|Run|calc.exe", strIniFile, "Commands", "calculator")

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Created default INI file", 2)
    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Failed to create INI: " err.Message, 4)
    }
}

/** @description LoadCommandsFromIni - Load user commands from INI file into mapCommands
    @returns {Map} - Map of phrase -> action data
    @details - Reads [Commands] section from INI file
             - Parses each line as phrase=group|type|action */
LoadCommandsFromIni() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile

    mapResult := Map()

    try {
        strSection := IniRead(strIniFile, "Commands")
    } catch {
        return mapResult
    }

    for strLine in StrSplit(strSection, "`n") {
        strLine := Trim(strLine)
        if (strLine = "") {
            continue
        }

        intEqualPos := InStr(strLine, "=")
        if (intEqualPos > 0) {
            strPhrase := Trim(SubStr(strLine, 1, intEqualPos - 1))
            strAction := Trim(SubStr(strLine, intEqualPos + 1))

            if (strPhrase != "" && strAction != "") {
                mapResult[StrLower(strPhrase)] := strAction
                LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Loaded: " strPhrase " => " strAction, 2)
            }
        }
    }

    return mapResult
}

/** @description LoadConfidenceSettings - Load Confidence Settings from INI */
LoadConfidenceSettings() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile, fltConfidenceThreshold, blnShowConfidence

    try {
        intThreshold := Integer(IniRead(strIniFile, "Settings", "confidenceThreshold", "40"))
        fltConfidenceThreshold := intThreshold / 100

        strShowConf := IniRead(strIniFile, "Settings", "showConfidence", "1")
        blnShowConfidence := (strShowConf = "1")

        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Confidence Threshold: " intThreshold "%, Show: " (blnShowConfidence ? "ON" : "OFF"), 2)
    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Failed to load confidence settings: " err.Message, 4)
        fltConfidenceThreshold := 0.40
        blnShowConfidence := true
    }
}

/** @description FFL - Format Function and Line number for logging
    @param {string} strFunc - Function name to format
    @param {integer} intLine - Line number to include
    @returns {string} - Formatted string padded to 60 chars */
FFL(strFunc, intLine) {
    return Format('{:-60}', strFunc . '(' . intLine . ')')
}

/** @description LogMsg - Write a message to the voice command log file
    @param {string} strMessage - Message text to log
    @param {integer} display - Verbosity level (0=silent, 1=normal, 2=detailed) */
LogMsg(strMessage, display := 0) {
    global strLogFile, intLoggingType

    if (intLoggingType & display) = display {
        strTimestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        try
            FileAppend(strTimestamp " - " strMessage "`n", strLogFile)
    }
}

/** @description CleanupVoice - Final cleanup when voice command script exits
    @param {string} exitReason - Reason for exit
    @param {integer} exitCode - Exit code from AutoHotkey */
CleanupVoice(exitReason, exitCode) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objContext, objStatusCircle

    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Voice command listener stopped (" exitReason ")", 2)

    BridgeDisconnect()
    StopAudioLevelMonitor()

    if (objStatusCircle != "") {
        try {
            objStatusCircle.Destroy()
        }
    }

    if (objContext != "") {
        try {
            ComObjConnect(objContext)
        }
    }

    ExitApp()
}

; Example function for voice-commands for calling internal functions
ExampleFunction() {
    MsgBox("This is an example of a function-call via voicecommand!", "Example")
}

; Start Commands function (can be called from voice or other triggers)
StartCommands() {
    global objGrammar, blnCommandsEnabled
    if (!blnCommandsEnabled) {
        blnCommandsEnabled := true
        objGrammar.CmdSetRuleState("cmd", 1)
        ToolTip("▶️ Commands ACTIVE")
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Commands enabled via StartCommands()", 2)
        UpdateTrayIcon()
        SetTimer(() => ToolTip(), -2000)
    }
}

; Stop Commands function (can be called from voice or other triggers)
PauseCommands() {
    global objGrammar, blnCommandsEnabled
    if (blnCommandsEnabled) {
        blnCommandsEnabled := false
        objGrammar.CmdSetRuleState("cmd", 0)
        ToolTip("⏸️ Commands PAUSED")
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Commands disabled via PauseCommands()", 2)
        UpdateTrayIcon()
        SetTimer(() => ToolTip(), -2000)
    }
}

;================= End of VC_Utils.ahk =================
