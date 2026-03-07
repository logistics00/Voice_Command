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
        IniWrite("-1", strIniFile, "Settings", "MicrophoneIndex")
        IniWrite("", strIniFile, "Settings", "MicrophoneName")
        IniWrite("0", strIniFile, "Settings", "TestMode")
        IniWrite("7", strIniFile, "Settings", "LoggingType")
        IniWrite("40", strIniFile, "Settings", "ConfidenceThreshold")
        IniWrite("1", strIniFile, "Settings", "ShowConfidence")

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
        intThreshold := Integer(IniRead(strIniFile, "Settings", "ConfidenceThreshold", "40"))
        fltConfidenceThreshold := intThreshold / 100

        strShowConf := IniRead(strIniFile, "Settings", "ShowConfidence", "1")
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

;============================================================
; BRIDGE - TCP Communication with Python Bridge
;============================================================

/** @description BridgeStart - Initialize Winsock, launch bridge.py, start connect-retry timer */
BridgeStart() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile, intBridgePid, strBridgeLanguage, strSpeakLanguage, intBridgeConnectAttempts

    strBridgeLanguage := IniRead(strIniFile, "Settings", "Language", "")
    strSpeakLanguage  := IniRead(strIniFile, "Settings", "SpeakLanguage", "default")

    ; Initialize Winsock
    wsa := Buffer(408, 0)
    if DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsa, "Int") != 0 {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "WSAStartup failed", 4)
        MsgBox("Failed to initialize Winsock.", "Bridge Error", "Icon!")
        return
    }

    strBridgeScript := A_ScriptDir "\python\bridge.py"
    if !FileExist(strBridgeScript) {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge script not found: " strBridgeScript, 4)
        MsgBox("Bridge script not found:`n" strBridgeScript, "Bridge Error", "Icon!")
        return
    }

    strCmd := 'python "' strBridgeScript '" "' strIniFile '"'
    try {
        Run(strCmd, A_ScriptDir, "Hide", &intBridgePid)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge launched, PID: " intBridgePid, 2)
    } catch as err {
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Failed to launch bridge: " err.Message, 4)
        MsgBox("Failed to launch Python bridge:`n" err.Message, "Bridge Error", "Icon!")
        return
    }

    intBridgeConnectAttempts := 0
    SetTimer(BridgeTryConnect, 500)
}

/** @description BridgeTryConnect - Retry TCP connect to bridge (called by timer every 500ms) */
BridgeTryConnect() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global intBridgeSocket, intBridgeConnectAttempts

    intBridgeConnectAttempts++
    if intBridgeConnectAttempts > 60 {
        SetTimer(BridgeTryConnect, 0)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge connect timeout after 30s", 4)
        MsgBox("Python bridge did not respond within 30 seconds.", "Bridge Timeout", "Icon!")
        return
    }

    sock := BridgeOpenSocket()
    if sock > 0 {
        SetTimer(BridgeTryConnect, 0)
        intBridgeSocket := sock
        SetTimer(BridgeReceive, 50)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Connected to bridge on attempt " intBridgeConnectAttempts, 2)
    }
}

/** @description BridgeOpenSocket - Create and connect a TCP socket to the bridge
    @returns {integer} - Socket handle > 0 on success, 0 on failure */
BridgeOpenSocket() {
    ; AF_INET=2, SOCK_STREAM=1, IPPROTO_TCP=6
    sock := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "UPtr")
    if (sock = 0xFFFFFFFFFFFFFFFF || sock = 0) {
        return 0
    }

    ; Build sockaddr_in (16 bytes): family, port, IP, padding
    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", DllCall("Ws2_32\htons", "UShort", 7891, "UShort"), addr, 2)
    NumPut("UInt",   DllCall("Ws2_32\inet_addr", "AStr", "127.0.0.1", "UInt"), addr, 4)

    if DllCall("Ws2_32\connect", "UPtr", sock, "Ptr", addr, "Int", 16, "Int") != 0 {
        DllCall("Ws2_32\closesocket", "UPtr", sock)
        return 0
    }

    ; Set non-blocking mode (FIONBIO)
    mode := Buffer(4, 0)
    NumPut("UInt", 1, mode, 0)
    DllCall("Ws2_32\ioctlsocket", "UPtr", sock, "Int", 0x8004667E, "Ptr", mode)

    return sock
}

/** @description BridgeSend - Send a command string to the Python bridge */
BridgeSend(strMsg) {
    global intBridgeSocket
    if intBridgeSocket = 0
        return

    strMsg .= "`n"
    buf    := Buffer(StrPut(strMsg, "UTF-8"))
    intLen := StrPut(strMsg, buf, "UTF-8") - 1  ; exclude null terminator
    DllCall("Ws2_32\send", "UPtr", intBridgeSocket, "Ptr", buf, "Int", intLen, "Int", 0)
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Sent: " RTrim(strMsg), 2)
}

/** @description BridgeReceive - Poll socket for incoming data (called by 50ms timer) */
BridgeReceive() {
    global intBridgeSocket, strBridgeBuffer
    if intBridgeSocket = 0
        return

    buf   := Buffer(4096, 0)
    bytes := DllCall("Ws2_32\recv", "UPtr", intBridgeSocket, "Ptr", buf, "Int", 4096, "Int", 0, "Int")
    if bytes > 0 {
        strBridgeBuffer .= StrGet(buf, bytes, "UTF-8")
        loop {
            intPos := InStr(strBridgeBuffer, "`n")
            if !intPos
                break
            strLine         := SubStr(strBridgeBuffer, 1, intPos - 1)
            strBridgeBuffer := SubStr(strBridgeBuffer, intPos + 1)
            HandleBridgeMessage(Trim(strLine))
        }
    }
    ; bytes = -1 with WSAEWOULDBLOCK (10035) means no data — normal for non-blocking socket
}

/** @description HandleBridgeMessage - Process a message received from the Python bridge */
HandleBridgeMessage(strMsg) {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge msg: " strMsg, 2)

    if InStr(strMsg, "STATUS:") = 1 {
        strStatus := SubStr(strMsg, 8)
        if strStatus = "ready" {
            ToolTip("Bridge ready")
            SetTimer(() => ToolTip(), -2000)
        }
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge STATUS: " strStatus, 2)

    } else if InStr(strMsg, "TEXT:") = 1 {
        strText := SubStr(strMsg, 6)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge TEXT: " strText, 2)
        ToolTip("Vosk: " strText)
        SetTimer(() => ToolTip(), -3000)
        SendText(strText " ")  ; type into active window with trailing space

    } else if InStr(strMsg, "ERROR:") = 1 {
        strErr := SubStr(strMsg, 7)
        LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge ERROR: " strErr, 4)
        ToolTip("Bridge Error: " strErr)
        SetTimer(() => ToolTip(), -5000)
    }
}

/** @description BridgeDisconnect - Send QUIT, close socket and clean up Winsock */
BridgeDisconnect() {
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . 'Started', 1)
    global intBridgeSocket

    SetTimer(BridgeReceive, 0)
    SetTimer(BridgeTryConnect, 0)

    if intBridgeSocket > 0 {
        BridgeSend("QUIT")
        Sleep(200)
        DllCall("Ws2_32\closesocket", "UPtr", intBridgeSocket)
        intBridgeSocket := 0
    }

    DllCall("Ws2_32\WSACleanup")
    LogMsg(FFL(A_ThisFunc, A_LineNumber) . "Bridge disconnected", 2)
}

;================= End of VC_Utils.ahk =================
