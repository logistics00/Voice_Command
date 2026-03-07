;================ VOICECOMMAND v1.8.0-A =================
; SAPI Voice Command Listener (Command Grammar)
; Uses SAPI COM objects to recognize voice commands
; Commands loaded from external INI file
;
; MODULAR VERSION - Split into 4 files:
;   Voice_Command_v2_A.ahk  - Entry point & globals (this file)
;   VC_Utils.ahk            - Utilities & helpers
;   VC_UI.ahk               - User interface & visuals
;   VC_Core.ahk             - SAPI voice recognition engine
;
; HISTORY:
;   v1.0.0 - v1.3.0 - Various fixes and tray menu
;   v1.3.1 - Added "list commands" voice command to show all commands
;          - Added built-in commands that are always available
;   v1.3.2 - Added F1 hotkey to toggle listening on/off
;          - Listening is ON by default when script starts
;          - Added blnListening global to track state
;   v1.3.3 - Added dynamic tray icons for listening state
;          - listening.ico when ON, Not Listening.ico when OFF
;   v1.4.0 - Redesigned Command Manager GUI with:
;          - Four input fields: Words Said, Group, Type, Action
;          - Three action buttons: Add, Edit, Delete
;          - ListView showing all commands in four columns
;          - Click row to populate input fields for editing
;          - Updated INI format: phrase=group|type|action
;   v1.4.1 - Fixed SetFont option "Normal" to "norm" for AHK v2
;   v1.4.2 - Fixed ListView options: removed + prefix, use LV0x20
;          - for full row select (AHK v2 syntax)
;   v1.5.0 - Added visual circle overlay indicator in upper right
;          - Blue circle when listening, red when not listening
;          - Circle updates with tray icon on state changes
;   v1.5.1 - Changed tray icons to system DLL icons
;          - Listening: aclui.dll icon 4
;          - Not listening: compstui.dll icon 69
;   v1.6.0 - Added Microphone Settings GUI with:
;          - List of available microphones with selection
;          - Real-time audio level meter (100ms updates)
;          - Test recognition to verify SAPI hears speech
;          - Save microphone name + index for verification
;          - Auto-show GUI on first run if no mic configured
;          - Pause and prompt if saved mic disappears
;          - Hot-swap microphone without restart
;   v1.7.0 - Added Confidence Threshold feature:
;          - Adjustable slider (0-100%) in Microphone Settings
;          - Rejects low-confidence recognitions
;          - Optional confidence display in tooltip
;          - Logs rejected commands with confidence level
;          - Default threshold: 40% (permissive)
;   v1.8.0 - Added the automatic recognition of the used language.
;            Added logging for the function flow
;            Added function name and line number to logging via extra function FFL
;            Added function-comments following "Quasi"-JSDoc
;            Added F2 hotkey to show Command Manager GUI
;            Added refresh of logging file at start of script
;            Changed LogEnabled => LoggingType to support different logging levels
;   v1.8.0-A - OPTIE A: Twee aparte grammars
;            - Control grammar (start/stop) blijft ALTIJD actief
;            - Main grammar wordt aan/uit gezet op basis van blnCommandsEnabled
;            - "Stop" pauzeert alle commando's behalve "Start"
;            - "Start" hervat normale werking
;   v1.8.1-A - MODULAR: Script opgesplitst in 4 bestanden
;            - Betere onderhoudbaarheid en overzicht

#Requires AutoHotkey v2.0.19+ 64-bit
#SingleInstance Force
Persistent

;============================================================
; GLOBAL VARIABLES
;============================================================

; SAPI Objects
global objRecognizer := ""
global objContext := ""
global objGrammar := ""
global objControlGrammar := ""  ; Separate grammar for start/stop
global objEventSink := ""

; Paths
global strLogFile := A_ScriptDir "\Voice_Command.log"
global strIniFile := A_ScriptDir "\Voice_Command.ini"

; Command Maps
global mapCommands := Map()
global mapBuiltInCommands := Map()
global mapControlCommands := Map()

; State Flags
global intTestMode := 0
global blnLogEnabled := true
global blnListening := true
global blnCommandsEnabled := true

; Voice mode: sapi | vosk | whisper | pause
global strVoiceMode := "sapi"
global speakLanguage := "default"   ; default = English, special = LocalLanguage= from INI
global strSpecialLanguage := ""     ; e.g. "nl" — read from INI at bridge startup

; TCP Bridge (Winsock client)
global intTcpSocket := 0
global intBridgePid := 0
global strTcpBuffer := ""
global strTcpHost := "127.0.0.1"
global intTcpPort := 7891

; Icon paths for listening state (system DLL icons)
global strIconListening := "C:\WINDOWS\system32\aclui.dll"
global intIconListeningNum := 4
global strIconNotListening := "C:\WINDOWS\system32\compstui.dll"
global intIconNotListeningNum := 69

; Status Circle Overlay settings
global objStatusCircle := ""
global intCircleSize := 30
global intCircleMargin := 20
global strColorListening := "0088FF"    ; Blue  — SAPI active
global strColorNotListening := "FF0000" ; Red   — listening OFF (F1)
global strColorPaused := "FFA500"       ; Orange — paused / SAPI commands off
global strColorVosk := "00CC44"         ; Green  — Vosk mode
global strColorWhisper := "9900CC"      ; Purple — Whisper mode (Phase 2)

; Command Manager GUI globals
global objCmdManagerGui := ""
global objLvCommands := ""
global objEdtWordsSaid := ""
global objEdtGroup := ""
global objDdlType := ""
global objEdtAction := ""
global intSelectedRow := 0

; Microphone Settings GUI globals
global objMicSettingsGui := ""
global objLvMicrophones := ""
global objProgressLevel := ""
global objTxtLevelPercent := ""
global objTxtMicStatus := ""
global objTxtTestResult := ""
global intCurrentMicIndex := 0
global strCurrentMicName := ""
global blnMicTestMode := false

; Confidence Threshold settings
global fltConfidenceThreshold := 0.40
global blnShowConfidence := true
global objSliderThreshold := ""
global objTxtThresholdValue := ""
global objChkShowConfidence := ""

; Dynamic SAPI language detection
global strLangId := ''

; Logging Type (bitwise: 1=flow, 2=test, 4=error, 7=all)
global intLoggingType := 0

;============================================================
; INCLUDE MODULES (order matters!)
;============================================================
#Include <General\Peep_v2>		; Library for displaying the contnts of AHK-vars
#Include <Project\Voice_Command_UI>		; 2. SECOND: User Interface - uses Utils but not Core
#Include <Project\Voice_Command_Utils>	; 1. FIRST: Utilities - no dependencies on other modules
#Include <Project\Voice_Command_Bridge>	; 4. Bridge: TCP connection to Python voice bridge
#Include <Project\Voice_Command_Core>		; 5. LAST: Core SAPI engine - uses Utils and UI functions

;============================================================
; INITIALIZATION
;============================================================

; Load logging type from INI
intLoggingType := Integer(IniRead(strIniFile, "Settings", "LoggingType", 0))

; Load circle size from INI — minimum 50 enforced internally
intCircleSize := Max(50, Integer(IniRead(strIniFile, "Gui", "intCircleSize", 50)))

; Load default language from INI — EN starts in English, LL starts in local language
if (IniRead(strIniFile, "Settings", "DefaultLanguage", "EN") = "LL")
    speakLanguage := "special"

; Refresh the log-file each time the script is started
if FileExist(strLogFile)
	FileDelete(strLogFile)

; Setup Built-in Commands (always available)
SetupBuiltInCommands()

; Setup Tray Menu
SetupTrayMenu()

; Initialize Voice Recognition
InitializeVoiceRecognition()

; Start Python bridge (auto-connect after SAPI is ready)
BridgeInit()

;============================================================
; HOTKEYS
;============================================================

; F1 Hotkey - Toggle Listening On/Off
F1:: ToggleListening()

; F2 Hotkey - Show Command Manager GUI
F2:: ShowCommandManagerGui()

; F3 Hotkey - Toggle SAPI/Vosk mode
F3:: ToggleVoskMode()

; F4 Hotkey - Toggle Vosk language (default/special)
F4:: ToggleLanguage()

;================= End of VOICECOMMAND Entry Point =================
