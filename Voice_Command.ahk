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
;          - Three input fields: Words Said, Type, Action
;          - Three action buttons: Add, Edit, Delete
;          - ListView showing all commands in four columns
;          - Click row to populate input fields for editing
;          - INI format: phrase=type|action
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
;            Changed logEnabled => loggingType to support different logging levels
;   v1.8.0-A - OPTIE A: Twee aparte grammars
;            - Control grammar (start/stop) moved to built-in grammar
;            - Soft pause (blnCommandsEnabled / "start"/"pause" voice commands) removed
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

; Voice mode: sapi | vosk | whisper
global strVoiceMode := "sapi"
global speakLanguage := "default"   ; default = English, special = localLanguage= from INI
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
global strColorListening := "0088FF"    ; Blue   — SAPI active
global strColorNotListening := "FF0000" ; Red    — listening OFF (F1)
global strColorVosk := "00CC44"         ; Green  — Vosk mode
global strColorWhisper := "9900CC"      ; Purple — Whisper mode
global strColorTestMode := "FFA500"     ; Orange — test mode active

; Command Manager / Microphone GUI globals
global goo := ""
global objManagerTab := ""
global lv1 := ""
global edtCommand := ""
global ddlType := ""
global edtAction := ""
global lv1Row := 0

; Microphone Settings GUI globals
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

; SAPI Speak Mode (0=log only, 1=tooltip+log for Hypothesis/FalseRecognition)
global intSapiSpeakMode := 0
global objSliderThreshold := ""
global objTxtThresholdValue := ""
global objChkshowConfidence := ""

; Dynamic SAPI language detection
global strLangId := ''

; Logging Type (bitwise: 1=flow, 2=test, 4=error, 7=all)
global intLoggingType := 0

;============================================================
; INCLUDE MODULES (order matters!)
;============================================================
#Include <General\Peep_v2>				; Library			- for displaying the contnts of AHK-vars
#Include <Project\Voice_Command_UI>		; User Interface	- uses Utils but not Core
#Include <Project\Voice_Command_Utils>	; Utilities			- no dependencies on other modules
#Include <Project\Voice_Command_Bridge>	; TCP				- connection to Python voice bridge
#Include <Project\Voice_Command_Core>	; Core SAPI engine	- uses Utils and UI functions

;============================================================
; INITIALIZATION
;============================================================

; Load logging type from INI
intLoggingType := Integer(IniRead(strIniFile, "Settings", "loggingType", 0))

; Load circle size from INI — minimum 50 enforced internally
intCircleSize := Max(50, Integer(IniRead(strIniFile, "Gui", "intCircleSize", 50)))

; Load default language from INI — EN starts in English, LL starts in local language
if (IniRead(strIniFile, "Settings", "defaultLanguage", "EN") = "LL")
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
HotKey(IniRead(strIniFile, 'HotKeys', 'listening', 'F1'), ToggleListeningMenu)
; Hotkey('^!s', ToggleListening())
; F1:: ToggleListening()

; F2 Hotkey - Show Command Manager GUI
HotKey(IniRead(strIniFile, 'HotKeys', 'mainGui', 'F2'), HotkeyMenu)
; Hotkey('^!s', ShowCommandManagerGui())
; F2:: ShowCommandManagerGui()

; F3 Hotkey - Cycle voice mode: SAPI -> Vosk -> Whisper -> SAPI
HotKey(IniRead(strIniFile, 'HotKeys', 'modus', 'F3'), CycleVoiceMode)
; Hotkey('^!s', CycleVoiceMode())
; F3:: CycleVoiceMode()

; F4 Hotkey - Toggle Vosk language (default/special)
HotKey(IniRead(strIniFile, 'HotKeys', 'language', 'F4'), ToggleLanguage)
; Hotkey('^!s', ToggleListening())
; F4:: ToggleLanguage()

; F5 Hotkey - Toggle Test Mode on/off
HotKey(IniRead(strIniFile, 'HotKeys', 'testMode', 'F5'), ToggleTestMode)
; F5:: ToggleTestMode()

;================= End of VOICECOMMAND Entry Point =================
