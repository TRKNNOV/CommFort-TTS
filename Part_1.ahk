; ================================================================
; ЧАСТЬ 1 ИЗ 4: ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ, СЛОВАРИ, ТРЕЙ И СЛЕЖЕНИЕ ЗА ЧАТОМ
; ================================================================
global TargetChannel := "main"
global IniFile := A_ScriptDir "\tts_settings.ini"

global BaseLogDir := EnvGet("APPDATA") "\CommFort\Default\History"
global BaseConfigDir := EnvGet("APPDATA") "\CommFort\Default\Config"
global ViewerIni := BaseLogDir "\ViewerSettings.ini"
global AccountsIni := BaseConfigDir "\Accounts.ini"

global lastPos := 0
global isEngineReady := false
global isMuted := false
global ActiveProfile := ""
global ActiveProfileGender := 0
global LastAuthor := "Кто-то"
global LastAuthorGender := 1
global LogFile := ""

global ttsNarrator := ""
global ttsUser := ""
global IgnoreList := ""
global SkipMyMessages := 0
global EnableDedWelcome := 0
global VoiceInputMode := 0
global TtsMode := 1

global LocalEnginePath := ""
global CloudApiKey := ""
global CloudFolderId := ""
global LocalMaleVoiceModel := "ru_RU-dmitri-medium.onnx"
global LocalFemaleVoiceModel := "ru_RU-irina-medium.onnx"
global CloudMaleVoiceCharacter := "filipp"
global CloudFemaleVoiceCharacter := "alena"

; Состояние движка голосового ввода Vosk
global voskModelPtr := 0
global voskDllLoaded := false
global isVoiceRecBusy := false

global MatWords := [
    "хуй", "хуе", "хули", "хуя", "хуи", "пизд", "ебан", "ебат", "ебл", "бля",
    "мудак", "муде", "гандон", "сука", "пидор", "пидар", "дроч", "шлюх",
    "проститут", "залуп", "манд", "хер", "курв", "на хер", "по хер", "голубец",
    "трах", "задорас", "педрил", "педер", "охуе", "ахуе", "склеи", "говн", "гавн"
]

global SmileyDict := Map(
    "tough", " [крутой] ", "smile", " [улыбается] ", "sad", " [грустит] ",
    "lol", " [смеётся] ", "wink", " [подмигивает] ", "shock", " [в шоке] ",
    "angry", " [злится] ", "cool", " [круто] ", "applause", " [аплодирует] ",
    "D", " [смеётся] ", "laugh", " [ржёт] ", "cry", " [плачет] ",
    "heart", " [любит] ", "thumbup", " [класс] ", "thumbdown", " [не нравится] ",
    "crazy", " [сходит с ума] ", "devil", " [чертёнок] ", "shame", " [стыдно] ",
    "sleep", " [спит] ", "bored", " [скучает] ", "kiss", " [целует] ", "thinking", " [думает] "
)

A_TrayMenu.Delete()
A_TrayMenu.Add("НАСТРОЙКИ", ShowSettingsGui)
A_TrayMenu.Add("Выход", (*) => ExitApp())
A_TrayMenu.Default := "НАСТРОЙКИ"
SetTrayIconState()
OnMessage(0x404, TrayClickCallback)

SetTimer(WatchCommFortProcess, 2000)

TrayClickCallback(wParam, lParam, msg, hwnd) {
    global isMuted
    if (lParam = 0x202) {
        isMuted := !isMuted
        SetTrayIconState()
        return 1
    }
}

SetTrayIconState() {
    global isMuted
    try {
        TraySetIcon("shell32.dll", isMuted ? 220 : 138)
    }
}

LogError(context, err := "") {
    logPath := A_ScriptDir "\tts_errors.log"
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    details := IsObject(err)
        ? (err.Message " (Строка: " err.Line ", Что: " err.What ")")
        : String(err)
    logLine := "[" timestamp "] [" context "] " details "`r`n"
    try {
        if (FileExist(logPath) && FileGetSize(logPath) > 1048576)
            FileDelete(logPath)
        FileAppend(logLine, logPath, "UTF-8")
    }
}

WatchCommFortProcess() {
    global isEngineReady, lastPos, LogFile, BaseLogDir, ViewerIni
    global ActiveProfile, ActiveProfileGender, TargetChannel, LastAuthor, ttsNarrator, isMuted

    if !ProcessExist("CommFort.exe") {
        if (isEngineReady) {
            SetTimer(ParseBinaryLog, 0)
            isEngineReady := false
            A_IconTip := "Озвучка CommFort (Ожидание чата...)"
        }
        return
    }

    CurrentMonthDir := FormatTime(, "yyyy_MM")
    FoundUser := ""
    if FileExist(ViewerIni) {
        try FoundUser := IniRead(ViewerIni, "Main", "CurrentUser", "")
    }
    if (FoundUser = "")
        FoundUser := EnvGet("USERNAME")

    if (isEngineReady && FoundUser != ActiveProfile) {
        SetTimer(ParseBinaryLog, 0)
        ActiveProfile := FoundUser
        ActiveProfileGender := DetectUserGender(ActiveProfile)
        LoadProfileSettings()
        LogFile := BaseLogDir "\" ActiveProfile "\" CurrentMonthDir "\Channels\" TargetChannel ".cflog"
        LastAuthor := ActiveProfile

        if FileExist(LogFile) {
            try {
                f := FileOpen(LogFile, "r-d")
                lastPos := f.Length
                f.Close()
            }
        } else {
            lastPos := 0
        }

        if (!isMuted) {
            ttsNarrator.Speak("Переключено на профиль " ActiveProfile, 0)
            Sleep(150)
        }
        SetTimer(ParseBinaryLog, 500)
        return
    }

    if !isEngineReady {
        ActiveProfile := FoundUser
        ActiveProfileGender := DetectUserGender(ActiveProfile)
        InitSpeechEngine()
    }
}
