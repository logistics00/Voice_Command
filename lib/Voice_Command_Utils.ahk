;================= VC_Utils.ahk =================
; Utilities & Helpers voor Voice Command
; Bevat: Logging, INI handling, Setup, Cleanup
;================================================

/** @description SetupBuiltInCommands - Setup built-in and control commands
    @details - Control commands (start/stop) go in separate grammar
             - Built-in commands in main grammar */
SetupBuiltInCommands() {
    LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global mapBuiltInCommands, mapControlCommands

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
    LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile

    try {
        IniWrite("", strIniFile, "Settings", "microphoneName")
        IniWrite("7", strIniFile, "Settings", "loggingType")
        IniWrite("40", strIniFile, "Settings", "confidenceThreshold")
        IniWrite("1", strIniFile, "Settings", "showConfidence")
        IniWrite("nl",    strIniFile, "Settings", "localLanguage")
        IniWrite("EN",    strIniFile, "Settings", "defaultLanguage")
        IniWrite("faster-whisper", strIniFile, "Settings", "dictateMode")
        IniWrite("",      strIniFile, "Settings", "openaiApiKey")

        ; Sample commands
        IniWrite("MsgBox|Hello World!", strIniFile, "Commands", "hello")
        IniWrite("Run|notepad.exe", strIniFile, "Commands", "notepad")
        IniWrite("Run|calc.exe", strIniFile, "Commands", "calculator")

        LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . "Created default INI file", 2)
    } catch as err {
        LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . "Failed to create INI: " err.Message, 4)
    }
}

/** @description LoadCommandsFromIni - Load user commands from INI file into mapCommands
    @returns {Map} - Map of phrase -> action data
    @details - Reads [Commands] section from INI file
             - Parses each line as phrase=type|action */
LoadCommandsFromIni() {
    LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . 'Started', 1)
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
                LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . "Loaded: " strPhrase " => " strAction, 2)
            }
        }
    }

    return mapResult
}

/** @description LoadConfidenceSettings - Load Confidence Settings from INI */
LoadConfidenceSettings() {
    LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile, fltConfidenceThreshold, blnShowConfidence, fltIniThreshold

    try {
        intThreshold := Integer(IniRead(strIniFile, "Settings", "confidenceThreshold", "40"))
        fltConfidenceThreshold := intThreshold / 100
        fltIniThreshold := fltConfidenceThreshold   ; save as anchor for adaptive logic

        strShowConf := IniRead(strIniFile, "Settings", "showConfidence", "1")
        blnShowConfidence := (strShowConf = "1")

        LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . "Confidence Threshold: " intThreshold "%, Show: " (blnShowConfidence ? "ON" : "OFF"), 2)
    } catch as err {
        LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . "Failed to load confidence settings: " err.Message, 4)
        fltConfidenceThreshold := 0.40
        fltIniThreshold := 0.40
        blnShowConfidence := true
    }
}

/** @description FFL				- Format FunctionName and LineNumber for logging
    @param {string} strFuncName		- Function name to format
    @param {integer} intLineNumber	- Line number to include
    @returns {string}				- Formatted string padded to 60 chars */
FFL(strScriptName,strFuncName, intLineNumber) {
    return Format('{:-60}', Format('{:-12}',strScriptName) . strFuncName . '(' . intLineNumber . ')')
}

/** @description LogMsg			- Write a message to the voice command log file
    @param {string} strMessage	- Message text to log
    @param {integer} display	- Verbosity level (0=silent, 1=normal, 2=detailed) */
LogMsg(strMessage, display := 0) {
    global strLogFile, intLoggingType

    if (intLoggingType & display) = display {
        strTimestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
		strDisplay := Format('{:-5}',(display = 1) ? "Flow" : (display = 2) ? "Debug" : (display = 4) ? "Error" : "Log")
        try
            FileAppend(strTimestamp " - " strDisplay " - " strMessage "`n", strLogFile)
    }
}

/** @description CleanupVoice - Final cleanup when voice command script exits
    @param {string} exitReason - Reason for exit
    @param {integer} exitCode - Exit code from AutoHotkey */
CleanupVoice(exitReason, exitCode) {
    LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global objContext, objStatusCircle

    LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . "Voice command listener stopped (" exitReason ")", 2)

    BridgeDisconnect()

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
    LogMsg(FFL('VC_Utils', A_ThisFunc, A_LineNumber) . 'Started', 1)
    MsgBox("This is an example of a function-call via voicecommand!", "Example")
}


;================= End of VC_Utils.ahk =================
