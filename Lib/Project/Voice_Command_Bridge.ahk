;================= VC_Bridge.ahk =================
; Python Bridge TCP Client for Voice Command
; Handles: bridge startup, TCP connection, mode cycling (SAPI/Vosk/Whisper), language toggle
;
; Protocol (AHK -> Python):
;   MODE:vosk | MODE:whisper | MODE:sapi | LANG:default | LANG:special | QUIT
; Protocol (Python -> AHK):
;   TEXT:<text> | STATUS:<msg> | ERROR:<msg>
;=================================================

;============================================================
; BRIDGE INITIALIZATION
;============================================================

/** @description BridgeKillOrphan - Send QUIT to any bridge already listening on port 7891
    @details Uses a raw Winsock connect; if successful sends QUIT and waits 800ms for shutdown. */
BridgeKillOrphan() {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    wsaData := Buffer(400, 0)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData, "Int") != 0)
        return

    hSock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if (hSock = -1) {
        DllCall("ws2_32\WSACleanup")
        return
    }

    sockAddr := Buffer(16, 0)
    NumPut("UShort", 2,                                                            sockAddr, 0)
    NumPut("UShort", DllCall("ws2_32\htons",    "UShort", 7891,        "UShort"), sockAddr, 2)
    NumPut("UInt",   DllCall("ws2_32\inet_addr", "AStr",  "127.0.0.1", "UInt"),   sockAddr, 4)

    if (DllCall("ws2_32\connect", "Ptr", hSock, "Ptr", sockAddr, "Int", 16, "Int") = 0) {
        ; Something is listening — send QUIT so it shuts down cleanly
        strQuit := "QUIT`n"
        intBufSize := StrPut(strQuit, "UTF-8")
        buf := Buffer(intBufSize, 0)
        StrPut(strQuit, buf, "UTF-8")
        DllCall("ws2_32\send", "Ptr", hSock, "Ptr", buf.Ptr, "Int", intBufSize - 1, "Int", 0)
        LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Sent QUIT to orphan bridge on port 7891", 2)
        Sleep(800)
    }

    DllCall("ws2_32\closesocket", "Ptr", hSock)
    DllCall("ws2_32\WSACleanup")
}

/** @description BridgeInit - Start Python bridge process and connect via TCP
    @details - Reads Language= from INI
             - Launches bridge.py with INI path as argument
             - Retries TCP connection up to 20 times (10 seconds total) */
BridgeInit() {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strIniFile, strSpecialLanguage, intBridgePid

    ; Read localLanguage= setting from INI
    strSpecialLanguage := Trim(IniRead(strIniFile, "Settings", "localLanguage", ""))
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "localLanguage setting: '" strSpecialLanguage "'", 2)

    ; Verify bridge script exists
    strBridgePath := A_ScriptDir "\python\bridge.py"
    if (!FileExist(strBridgePath)) {
        LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Bridge not found: " strBridgePath, 4)
        MsgBox("Python bridge not found:`n" strBridgePath "`n`nVosk/Whisper unavailable.", "Bridge Missing", "Icon!")
        return
    }

    ; Send QUIT to any orphan bridge already listening on port 7891
    BridgeKillOrphan()

    ; Launch bridge process (hidden window, no console visible)
    try {
        Run('python "' strBridgePath '" "' strIniFile '"',, "Hide", &intBridgePid)
        LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Bridge started (PID: " intBridgePid ")", 2)
    } catch as err {
        LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Failed to start bridge: " err.Message, 4)
        MsgBox("Failed to start Python bridge:`n" err.Message "`n`nVosk/Whisper unavailable.", "Bridge Error", "Icon!")
        return
    }

    ; Retry TCP connection — bridge loads Vosk models before starting the server
    ToolTip("Connecting to Python bridge, please wait...")
    Loop 20 {
        Sleep(500)
        if (BridgeConnect()) {
            ToolTip()
            LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Bridge connected (attempt " A_Index ")", 2)
            if (speakLanguage = "special")
                BridgeSend("LANG:special")
            return
        }
    }

    ToolTip()
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Bridge connection failed after 20 attempts", 4)
    MsgBox("Could not connect to Python bridge.`n`nVosk/Whisper unavailable.", "Bridge Error", "Icon!")
}

;============================================================
; TCP CONNECTION
;============================================================

/** @description BridgeConnect - Open Winsock TCP connection to Python bridge
    @returns {integer} - 1 on success, 0 on failure */
BridgeConnect() {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global intTcpSocket, strTcpHost, intTcpPort

    ; Initialize Winsock 2.2
    wsaData := Buffer(400, 0)
    if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData, "Int") != 0) {
        LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "WSAStartup failed", 4)
        return 0
    }

    ; Create TCP socket: AF_INET=2, SOCK_STREAM=1, IPPROTO_TCP=6
    hSock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if (hSock = -1) {
        DllCall("ws2_32\WSACleanup")
        return 0
    }

    ; Build sockaddr_in (16 bytes)
    sockAddr := Buffer(16, 0)
    NumPut("UShort", 2,                                                               sockAddr, 0)  ; sin_family = AF_INET
    NumPut("UShort", DllCall("ws2_32\htons",    "UShort", intTcpPort, "UShort"),     sockAddr, 2)  ; sin_port (network byte order)
    NumPut("UInt",   DllCall("ws2_32\inet_addr", "AStr",  strTcpHost, "UInt"),       sockAddr, 4)  ; sin_addr (network byte order)

    ; Connect to bridge
    if (DllCall("ws2_32\connect", "Ptr", hSock, "Ptr", sockAddr, "Int", 16, "Int") != 0) {
        DllCall("ws2_32\closesocket", "Ptr", hSock)
        DllCall("ws2_32\WSACleanup")
        return 0
    }

    ; Set non-blocking mode: FIONBIO = 0x8004667E = -2147195266 as signed Int
    pMode := Buffer(4, 0)
    NumPut("UInt", 1, pMode)
    DllCall("ws2_32\ioctlsocket", "Ptr", hSock, "Int", -2147195266, "Ptr", pMode, "Int")

    intTcpSocket := hSock

    ; Start 50ms receive poll timer
    SetTimer(BridgeReceiveLoop, 50)

    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "TCP connected to " strTcpHost ":" intTcpPort, 2)
    return 1
}

/** @description BridgeSend - Send a message line to the Python bridge
    @param {string} strMsg - Message to send (newline is appended automatically) */
BridgeSend(strMsg) {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global intTcpSocket
    if (intTcpSocket = 0)
        return

    strMsg .= "`n"
    intBufSize := StrPut(strMsg, "UTF-8")          ; includes null terminator
    buf := Buffer(intBufSize, 0)
    StrPut(strMsg, buf, "UTF-8")
    DllCall("ws2_32\send", "Ptr", intTcpSocket, "Ptr", buf.Ptr, "Int", intBufSize - 1, "Int", 0)
}

/** @description BridgeReceiveLoop - Poll TCP socket for incoming data (50ms timer)
    @details - Non-blocking recv; buffers partial lines; dispatches complete lines */
BridgeReceiveLoop() {
    global intTcpSocket, strTcpBuffer
    if (intTcpSocket = 0)
        return

    buf := Buffer(4096, 0)
    bytesRecv := DllCall("ws2_32\recv", "Ptr", intTcpSocket, "Ptr", buf.Ptr, "Int", 4096, "Int", 0, "Int")
    if (bytesRecv <= 0)
        return

    strTcpBuffer .= StrGet(buf.Ptr, bytesRecv, "UTF-8")

    ; Dispatch all complete lines
    while (intPos := InStr(strTcpBuffer, "`n")) {
        strLine := Trim(SubStr(strTcpBuffer, 1, intPos - 1), " `r`t")
        strTcpBuffer := SubStr(strTcpBuffer, intPos + 1)
        if (strLine != "")
            BridgeHandleMessage(strLine)
    }
}

/** @description BridgeHandleMessage - Dispatch a complete message received from bridge
    @param {string} strMsg - One complete message line */
BridgeHandleMessage(strMsg) {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Received: " strMsg, 2)

    if (SubStr(strMsg, 1, 5) = "TEXT:") {
        strText := SubStr(strMsg, 6)
        if (strText != "") {
            SendText(strText " ")
            LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Typed: " strText, 2)
        }
    } else if (SubStr(strMsg, 1, 7) = "STATUS:") {
        LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Bridge status: " SubStr(strMsg, 8), 2)
    } else if (SubStr(strMsg, 1, 6) = "ERROR:") {
        strErr := SubStr(strMsg, 7)
        LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Bridge error: " strErr, 4)
        ToolTip("Bridge: " strErr)
        SetTimer(() => ToolTip(), -10000)
    }
}

/** @description BridgeDisconnect - Send QUIT, close TCP socket, stop bridge process */
BridgeDisconnect() {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global intTcpSocket, intBridgePid

    SetTimer(BridgeReceiveLoop, 0)          ; Stop receive timer

    if (intTcpSocket != 0) {
        BridgeSend("QUIT")
        ProcessWaitClose(intBridgePid, 2000)
        if ProcessExist(intBridgePid)
          ProcessClose(intBridgePid)
        DllCall("ws2_32\closesocket", "Ptr", intTcpSocket)
        DllCall("ws2_32\WSACleanup")
        intTcpSocket := 0
    }

    if (intBridgePid != 0) {
        try {
            ProcessClose(intBridgePid)
        }
        intBridgePid := 0
    }

    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Bridge disconnected", 2)
}

;============================================================
; MODE SWITCHING
;============================================================

/** @description CycleVoiceMode - F3 handler: cycle SAPI -> Vosk -> Whisper -> SAPI */
CycleVoiceMode(*) {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strVoiceMode, blnListening, intTcpSocket

    if (!blnListening) {
        ToolTip("Cannot switch mode -- listening is OFF")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (intTcpSocket = 0) {
        ToolTip("Python bridge not connected")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (strVoiceMode = "sapi")
	    SwitchToVosk()
    else if (strVoiceMode = "vosk")
		SwitchToWhisper()
    else if (strVoiceMode = "whisper")
		SwitchToSapi()
}

/** @description SwitchToVosk - Pause SAPI grammar and activate Vosk mode */
SwitchToVosk() {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strVoiceMode, objGrammar, objControlGrammar

    ; Pause both SAPI grammars so mic is free for Python
    try {
        objGrammar.CmdSetRuleState("cmd", 0)
        objControlGrammar.CmdSetRuleState("control", 0)
    }

    strVoiceMode := "vosk"
    BridgeSend("MODE:vosk")
    UpdateStatusCircle()
    ToolTip("Mode: Vosk (sentence recognition)")
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Switched to Vosk", 2)
    SetTimer(() => ToolTip(), -2000)
}

/** @description SwitchToWhisper - Pause SAPI grammar and activate Whisper dictation mode */
SwitchToWhisper() {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strVoiceMode, objGrammar, objControlGrammar

    ; Pause both SAPI grammars so mic is free for Python
    try {
        objGrammar.CmdSetRuleState("cmd", 0)
        objControlGrammar.CmdSetRuleState("control", 0)
    }

    strVoiceMode := "whisper"
    BridgeSend("MODE:whisper")
    UpdateStatusCircle()
    ToolTip("Mode: Whisper (dictation)")
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Switched to Whisper", 2)
    SetTimer(() => ToolTip(), -2000)
}

/** @description SwitchToSapi - Return from Vosk/Whisper to SAPI mode and resume grammar */
SwitchToSapi() {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global strVoiceMode, objGrammar, objControlGrammar, blnListening

    BridgeSend("MODE:sapi")
    strVoiceMode := "sapi"

    ; Restore both grammars when listening
    if (blnListening) {
        try {
            objControlGrammar.CmdSetRuleState("control", 1)
        }
        try {
            objGrammar.CmdSetRuleState("cmd", 1)
        }
    }

    UpdateStatusCircle()
    ToolTip("Mode: SAPI (command recognition)")
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Switched to SAPI", 2)
    SetTimer(() => ToolTip(), -2000)
}

/** @description ToggleLanguage - F4 handler: toggle Vosk language between default and special */
ToggleLanguage(*) {
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . 'Started', 1)
    global speakLanguage, strSpecialLanguage, intTcpSocket

    if (intTcpSocket = 0) {
        ToolTip("Python bridge not connected")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (strSpecialLanguage = "") {
        ToolTip("No local language configured -- add localLanguage=nl to INI")
        SetTimer(() => ToolTip(), -3000)
        return
    }

    if (speakLanguage = "default") {
        speakLanguage := "special"
        BridgeSend("LANG:special")
        ToolTip("Language: " strSpecialLanguage)
    } else {
        speakLanguage := "default"
        BridgeSend("LANG:default")
        ToolTip("Language: English (default)")
    }

    UpdateStatusCircle()
    LogMsg(FFL('VC_Bridge', A_ThisFunc, A_LineNumber) . "Language toggled: " speakLanguage, 2)
    SetTimer(() => ToolTip(), -2000)
}

;================= End of VC_Bridge.ahk =================
