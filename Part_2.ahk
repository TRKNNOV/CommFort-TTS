; ================================================================
; ЧАСТЬ 2 ИЗ 4: ИНИЦИАЛИЗАЦИЯ ДВИЖКОВ, НАСТРОЙКИ И СЕТЕВОЕ ПРИВЕТСТВИЕ
; ================================================================
DetectUserGender(username) {
    global AccountsIni
    if !FileExist(AccountsIni)
        return 0
    try {
        count := Integer(IniRead(AccountsIni, "Accounts", "Count", "0"))
        loop count {
            idx := A_Index - 1
            login := IniRead(AccountsIni, "Account_" idx, "Login", "")
            if (StrLower(Trim(login)) = StrLower(Trim(username)))
                return Integer(IniRead(AccountsIni, "Account_" idx, "CurrentIcon", "0"))
        }
    }
    return 0
}

InitSpeechEngine() {
    global isEngineReady, lastPos, LogFile, ttsNarrator, ttsUser, BaseLogDir, TargetChannel
    global LastAuthor, ActiveProfile, ActiveProfileGender, isMuted, VoiceInputMode

    try {
        ttsNarrator := ComObject("SAPI.SpVoice")
        ttsUser := ComObject("SAPI.SpVoice")
    } catch as e {
        LogError("InitSpeechEngine", e)
        return
    }

    LoadProfileSettings()

    CurrentMonthDir := FormatTime(, "yyyy_MM")
    LogFile := BaseLogDir "\" ActiveProfile "\" CurrentMonthDir "\Channels\" TargetChannel ".cflog"
    LastAuthor := ActiveProfile

    if FileExist(LogFile) {
        try {
            fileObj := FileOpen(LogFile, "r-d")
            fileObj.Seek(0, 2)
            lastPos := fileObj.Pos
            fileObj.Close()
        }
    } else {
        lastPos := 0
    }

    isEngineReady := true
    A_IconTip := "Озвучка CommFort (Активна: " ActiveProfile ")"

  if (!isMuted) {
      ttsNarrator.Speak("Голосовой модуль синхронизирован.", 1)
      while (ttsNarrator.Status.RunningState != 1) {
          Sleep(50)
      }

      if (EnableDedWelcome == 1) {
          Sleep(200)
          userName := Trim(ActiveProfile)
          isFemale := IsUserFemale(userName, ActiveProfileGender, false)

          if (isFemale) {
              welcomePhrases := [
                  "Здравствуй " userName ". Проходи галубушка на кордон к самавару паближе.",
                  "О! " userName " заходи красавица не тапчись на пароге.",
                  "Дабро пожаловать на хутор Хлебный " userName ". Распа лагайся.",
                  "О! " userName " пожаловала. Чай ку? налить? с дороги"
              ]
          } else {
              welcomePhrases := [
                  "Здорова " userName ". Проходи на кордон к самавару паближе.",
                  "О! " userName " заходи мил человек не тапчись на пароге.",
                  "Дабро пожаловать на хутор Хлебный " userName ". Распа лагайся.",
                  "О! " userName " пожаловал. Чай ку? налить? с дороги"
              ]
          }

          randIdx := Random(1, welcomePhrases.Length)
          oldAuthor := LastAuthor
          LastAuthor := "Дед Ваня"
          SpeakByVoiceId(welcomePhrases[randIdx], "", false, false, ttsUser.Volume, ttsUser.Rate)
          LastAuthor := oldAuthor
      }
  }

    ; Отправляем сетевой тег своего голоса в чат (если включено)
    SendMySharedVoiceTag()

    ; Предварительно загружаем модель Vosk в память (если включен голосовой ввод)
    if (VoiceInputMode == 1)
        InitVoskEngine()

    SetTimer(ParseBinaryLog, 500)
}

InitVoskEngine() {
    global voskModelPtr, voskDllLoaded
    if (voskDllLoaded)
        return

    voskDir := A_ScriptDir "\vosk"
    voskDll := voskDir "\libvosk.dll"
    modelDir := voskDir "\model"

    if !(FileExist(voskDll) && DirExist(modelDir))
        return

    try {
        DllCall("SetDllDirectoryW", "Str", voskDir)
        if !DllCall("LoadLibraryW", "Str", voskDll, "Ptr")
            return

        DllCall("libvosk\vosk_set_log_level", "Int", -1, "Int")

        utf8Len := StrPut(modelDir, "UTF-8")
        pathBuf := Buffer(utf8Len)
        StrPut(modelDir, pathBuf, "UTF-8")

        voskModelPtr := DllCall("libvosk\vosk_model_new", "Ptr", pathBuf, "Ptr")
        if (voskModelPtr)
            voskDllLoaded := true
    } catch as e {
        LogError("InitVoskEngine", e)
    }
}

LoadProfileSettings() {
    global IniFile, ActiveProfile, ttsNarrator, ttsUser, IgnoreList, SkipMyMessages, TargetChannel
    global TtsMode, LocalEnginePath, CloudApiKey, CloudFolderId, VoiceInputMode

    TargetChannel := IniRead(IniFile, ActiveProfile, "TargetChannel", "main")
    SavedVoiceId := IniRead(IniFile, ActiveProfile, "NarratorVoiceId", "")
    NarratorVol := IniRead(IniFile, ActiveProfile, "NarratorVolume", "100")
    NarratorRate := IniRead(IniFile, ActiveProfile, "NarratorRate", "0")
    UserVol := IniRead(IniFile, ActiveProfile, "UserVolume", "100")
    UserRate := IniRead(IniFile, ActiveProfile, "UserRate", "0")
    IgnoreList := IniRead(IniFile, ActiveProfile, "IgnoreList", "Бот1,Реклама,Служба")
    SkipMyMessages := Integer(IniRead(IniFile, ActiveProfile, "SkipMyMessages", "0"))
global EnableDedWelcome
EnableDedWelcome := Integer(IniRead(IniFile, ActiveProfile, "EnableDedWelcome", "0"))
    VoiceInputMode := Integer(IniRead(IniFile, ActiveProfile, "VoiceInputMode", "0"))
    TtsMode := Integer(IniRead(IniFile, ActiveProfile, "TtsMode", "1"))
    LocalEnginePath := IniRead(IniFile, ActiveProfile, "LocalEnginePath", "")
if (LocalEnginePath = "" && DirExist(A_ScriptDir "\piper"))
    LocalEnginePath := A_ScriptDir "\piper"
    CloudApiKey := IniRead(IniFile, ActiveProfile, "CloudApiKey", "")
    CloudFolderId := IniRead(IniFile, ActiveProfile, "CloudFolderId", "")

    try {
        allVoicesObj := ttsNarrator.GetVoices()
        if (SavedVoiceId = "" && allVoicesObj.Count > 0) {
            ttsNarrator.Voice := allVoicesObj.Item(0)
        } else {
            loop allVoicesObj.Count {
                v := allVoicesObj.Item(A_Index - 1)
                if (v.Id = SavedVoiceId) {
                    ttsNarrator.Voice := v
                    break
                }
            }
        }
    }

    ttsNarrator.Volume := NarratorVol
    ttsNarrator.Rate := NarratorRate
    ttsUser.Volume := UserVol
    ttsUser.Rate := UserRate
}

SendMySharedVoiceTag() {
    global IniFile, ActiveProfile, ActiveProfileGender

    sec := "MySharedVoice_" ActiveProfile
    isEnabled := Integer(IniRead(IniFile, sec, "Enabled", "0"))
    vKey := IniRead(IniFile, sec, "VoiceKey", "")
    vRate := IniRead(IniFile, sec, "Rate", "0")

    if (isEnabled != 1 || vKey = "")
        return

    if !ProcessExist("CommFort.exe")
        return

    try {
        ; Даём клиенту время завершить подключение к серверу при старте Windows
        Sleep(3000)

        ; Активируем окно чата только если оно доступно (без принудительного показа скрытых служебных окон)
        if !WinExist("ahk_exe CommFort.exe")
            return

        WinActivate("ahk_exe CommFort.exe")
        if !WinWaitActive("ahk_exe CommFort.exe", , 2)
            return

        Sleep(200)

        isFemale := IsUserFemale(ActiveProfile, ActiveProfileGender, false)
        if (isFemale) {
            greetings := [
                "Всем приветик!",
                "Приветик всем в чате!",
                "Всем доброго дня и хорошего настроения!",
                "Привет, чест ной компании! Я на месте."
            ]
        } else {
            greetings := [
                "Здорова, народ!",
                "Всем привет!",
                "Приветствую всех в чате!",
                "Всем доброго времени суток!"
            ]
        }

        greetText := greetings[Random(1, greetings.Length)]
        payload := '[url="tts:' vKey '|' vRate '"]' greetText '[/url]'

        savedClip := ClipboardAll()
        A_Clipboard := payload
        if !ClipWait(1) {
            A_Clipboard := savedClip
            return
        }

        Send("^v")
        Sleep(100)
        Send("{Enter}")
        Sleep(150)

        A_Clipboard := savedClip
    } catch as e {
        LogError("SendMySharedVoiceTag", e)
    }
}
