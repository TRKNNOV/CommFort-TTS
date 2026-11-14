; ================================================================
; ЧАСТЬ 4 ИЗ 4: GUI ИНТЕРФЕЙС, НАСТРОЙКИ И ГОЛОСОВОЙ ВВОД (VOSK / WIN)
; ================================================================
ShowSettingsGui(*) {
    TtsGuiManager.BuildAndShow()
}

class TtsGuiManager {
    static guiObj := ""
    static comboCustomNick := ""
    static dropCustomVoice := ""
    static sliderCustomVol := ""
    static sliderCustomRate := ""
    static dropChannel := ""
    static dropList := ""
    static sliderNarratorVol := ""
    static sliderNarratorRate := ""
    static sliderUserVol := ""
    static sliderUserRate := ""
    static editIgnore := ""
    static chkSkipMy := ""
    static chkVoiceInput := ""
    static chkAutoStart := ""
    static ActiveNicks := []
    static NarratorVoicesNames := []
    static NarratorVoicesIds := []
    static HybridVoicesNames := []
    static HybridVoicesIds := []
    static dropTtsMode := ""
    static btnConfigureAi := ""
    static currentLocalPath := ""
    static currentCloudKey := ""
    static currentCloudFolder := ""
    static dropMySharedVoice := ""
    static sliderMySharedRate := ""
    static chkSendMyVoice := ""
static chkDedWelcome := ""

    static RefreshVoiceLists(preserveSelection := true) {
        global IniFile, ttsNarrator, ActiveProfile

        prevNarratorId := ""
        prevCustomId := ""
        if (preserveSelection && IsObject(this.dropList) && this.dropList.Value > 0 && this.dropList.Value <= this.NarratorVoicesIds.Length)
            prevNarratorId := this.NarratorVoicesIds[this.dropList.Value]
        else
            prevNarratorId := IniRead(IniFile, ActiveProfile, "NarratorVoiceId", "")

        if (preserveSelection && IsObject(this.dropCustomVoice) && this.dropCustomVoice.Value > 0 && this.dropCustomVoice.Value <= this.HybridVoicesIds.Length)
            prevCustomId := this.HybridVoicesIds[this.dropCustomVoice.Value]

        this.NarratorVoicesNames := []
        this.NarratorVoicesIds := []
        this.HybridVoicesNames := []
        this.HybridVoicesIds := []

        allVoices := ttsNarrator.GetVoices()
        loop allVoices.Count {
            v := allVoices.Item(A_Index - 1)
            desc := v.GetDescription() " (SAPI)"
            this.NarratorVoicesNames.Push(desc)
            this.NarratorVoicesIds.Push(v.Id)
            this.HybridVoicesNames.Push(desc)
            this.HybridVoicesIds.Push(v.Id)
        }

        this.HybridVoicesNames.Push("[ИИ] Авто-выбор по полу")
        this.HybridVoicesIds.Push("[ИИ] Авто-выбор по полу")

        if (this.currentLocalPath != "" && DirExist(this.currentLocalPath)) {
            slash := Chr(92)
            cleanDir := RTrim(this.currentLocalPath, slash)
            loop Files, cleanDir slash "*.onnx" {
                label := "[Piper] " A_LoopFileName
                this.NarratorVoicesNames.Push(label)
                this.NarratorVoicesIds.Push(label)
                this.HybridVoicesNames.Push(label)
                this.HybridVoicesIds.Push(label)
            }
        }

        for yVoice in ["filipp", "alena", "ermil", "jane", "omazh", "zahar"] {
            label := "[Yandex] " yVoice
            this.NarratorVoicesNames.Push(label)
            this.NarratorVoicesIds.Push(label)
            this.HybridVoicesNames.Push(label)
            this.HybridVoicesIds.Push(label)
        }

        if IsObject(this.dropList) {
            try {
                this.dropList.Delete()
                this.dropList.Add(this.NarratorVoicesNames)
                chosen := 1
                for idx, id in this.NarratorVoicesIds {
                    if (id = prevNarratorId) {
                        chosen := idx
                        break
                    }
                }
                this.dropList.Choose(chosen)
            }
        }

        if IsObject(this.dropCustomVoice) {
            try {
                this.dropCustomVoice.Delete()
                this.dropCustomVoice.Add(this.HybridVoicesNames)
                chosenCustom := 1
                for idx, id in this.HybridVoicesIds {
                    if (id = prevCustomId) {
                        chosenCustom := idx
                        break
                    }
                }
                this.dropCustomVoice.Choose(chosenCustom)
            }
        }
    }

    static BuildAndShow() {
        global IniFile, isEngineReady, ttsNarrator, ttsUser, IgnoreList, ActiveProfile, SkipMyMessages, TargetChannel, BaseLogDir, VoiceInputMode, ViewerIni
        if !isEngineReady {
            if (ActiveProfile = "") {
                if FileExist(ViewerIni) {
                    try ActiveProfile := IniRead(ViewerIni, "Main", "CurrentUser", "")
                }
                if (ActiveProfile = "")
                    ActiveProfile := EnvGet("USERNAME")
            }
            if !IsObject(ttsNarrator) {
                try {
                    ttsNarrator := ComObject("SAPI.SpVoice")
                    ttsUser := ComObject("SAPI.SpVoice")
                    LoadProfileSettings()
                }
            }
        }

        if IsObject(this.guiObj) {
            try {
                this.guiObj.Show()
                return
            }
        }

        this.ActiveNicks := []
        AvailableChannels := []

        CurrentMonthDir := FormatTime(, "yyyy_MM")
        UserChannelsPath := BaseLogDir "\" ActiveProfile "\" CurrentMonthDir "\Channels"
        loop Files, UserChannelsPath "\*.cflog" {
            nameNoExt := RegExReplace(A_LoopFileName, "\.cflog$")
            AvailableChannels.Push(nameNoExt)
        }
        if (AvailableChannels.Length = 0)
            AvailableChannels.Push("main")

        this.currentLocalPath := IniRead(IniFile, ActiveProfile, "LocalEnginePath", "")
if (this.currentLocalPath = "" && DirExist(A_ScriptDir "\piper"))
    this.currentLocalPath := A_ScriptDir "\piper"
        this.currentCloudKey := IniRead(IniFile, ActiveProfile, "CloudApiKey", "")
        this.currentCloudFolder := IniRead(IniFile, ActiveProfile, "CloudFolderId", "")

        this.dropList := ""
        this.dropCustomVoice := ""
        this.RefreshVoiceLists(false)

        NickMap := Map()
        try {
            iniContent := FileRead(IniFile)
            loop Parse, iniContent, "`n", "`r" {
                if RegExMatch(A_LoopField, "i)^\[Custom_(.+)\]$", &match) {
                    uNick := match[1]
                    if !NickMap.Has(StrLower(uNick)) {
                        NickMap[StrLower(uNick)] := uNick " *"
                        this.ActiveNicks.Push(uNick " *")
                    }
                }
            }
        }

        TargetLog := UserChannelsPath "\" TargetChannel ".cflog"
        if FileExist(TargetLog) {
            try {
                fileObj := FileOpen(TargetLog, "r-d")
                fSize := fileObj.Length
                readPos := (fSize > 1048576) ? fSize - 1048576 : 0
                fileObj.Seek(readPos, 0)
                bToRead := fSize - readPos
                if (bToRead > 32) {
                    buf := Buffer(bToRead)
                    fileObj.RawRead(buf)
                    offset := 0
                    while (offset < bToRead - 10) {
                        if (NumGet(buf, offset, "UChar") != 188) {
                            offset += 1
                            continue
                        }
                        blockLength := NumGet(buf, offset + 1, "UShort") + (NumGet(buf, offset + 3, "UChar") << 16)
                        if (offset + 4 + blockLength > bToRead || blockLength <= 0) {
                            offset += 1
                            continue
                        }
                        dataOffset := offset + 4
                        endOfBlock := dataOffset + blockLength
                        while (dataOffset < endOfBlock - 4) {
                            msgVal := NumGet(buf, dataOffset, "UChar")
                            if (msgVal = 110 || msgVal = 111) {
                                genderVal := NumGet(buf, dataOffset + 1, "UChar")
                                if (genderVal <= 2 || genderVal == 64) {
                                    nameLen := NumGet(buf, dataOffset + 2, "UChar")
                                    if (nameLen > 1 && nameLen < 30 && (dataOffset + 3 + (nameLen * 2) <= endOfBlock)) {
                                        logAuthor := StrGet(buf.Ptr + dataOffset + 3, nameLen, "UTF-16")
                                        if (logAuthor != "" && RegExMatch(logAuthor, "^[a-zA-Zа-яА-ЯёЁ0-9_\-\s\.]+$")) {
                                            logAuthor := Trim(logAuthor)
                                            if (logAuthor != "" && !NickMap.Has(StrLower(logAuthor))) {
                                                NickMap[StrLower(logAuthor)] := logAuthor
                                                this.ActiveNicks.Push(logAuthor)
                                            }
                                        }
                                    }
                                }
                            }
                            dataOffset += 1
                        }
                        offset += 4 + blockLength
                    }
                }
                fileObj.Close()
            }
        }

        if (this.ActiveNicks.Length = 0)
            this.ActiveNicks.Push(ActiveProfile)
        this.guiObj := Gui("+AlwaysOnTop", "Управление TTS")
        this.guiObj.OnEvent("Close", (*) => (this.guiObj.Destroy(), this.guiObj := ""))
        this.guiObj.SetFont("s10", "Segoe UI")
        this.guiObj.SetFont("s12 Bold")
        this.guiObj.Add("Text", "w360 Center", "Управление TTS")
        this.guiObj.SetFont("s10 cRed Bold")
        this.guiObj.Add("Text", "w360 Center y+4", "Профиль: " ActiveProfile)
        this.guiObj.SetFont("s10 cDefault Norm")

        Tab := this.guiObj.Add("Tab3", "w360 h660 x10 y+15", ["Основные", "Персональные голоса", "О программе"])

        ; ---------------- ВКЛАДКА 1: ОСНОВНЫЕ ----------------
        Tab.UseTab(1)

        this.guiObj.Add("Text", "x25 y+15", "Выбор канала для озвучивания:")
        this.dropChannel := this.guiObj.Add("DropDownList", "w330 Choose1", AvailableChannels)
        for idx, ch in AvailableChannels {
            if (StrLower(ch) = StrLower(TargetChannel)) {
                this.dropChannel.Choose(idx)
                break
            }
        }

        this.guiObj.Add("Text", "y+12", "Режим работы TTS:")
        this.dropTtsMode := this.guiObj.Add("DropDownList", "w210 Choose1 x25 y+4", ["Стандартный SAPI", "Локальный ИИ (Piper)", "Облачный ИИ (Yandex)"])
        this.dropTtsMode.Choose(TtsMode)
        this.dropTtsMode.OnEvent("Change", ObjBindMethod(this, "ToggleTtsModeFields"))
        this.btnConfigureAi := this.guiObj.Add("Button", "w110 x245 yp-1 h28", "⚙ Настроить...")
        this.btnConfigureAi.OnEvent("Click", ObjBindMethod(this, "OpenAiModalWindow"))

        this.guiObj.SetFont("cBlue Bold")
        this.guiObj.Add("Text", "w330 Center x25 y+16", "--- ГОЛОС ЧАТА ---")
        this.guiObj.SetFont("cDefault Norm")
        this.dropList := this.guiObj.Add("DropDownList", "w292 Choose1 y+6 x25", this.NarratorVoicesNames)
        btnPreviewNarrator := this.guiObj.Add("Button", "w34 x321 yp-1 h26", "🔊")
        btnPreviewNarrator.OnEvent("Click", ObjBindMethod(this, "PreviewNarratorVoice"))

        savedVoice := IniRead(IniFile, ActiveProfile, "NarratorVoiceId", "")
        for idx, id in this.NarratorVoicesIds {
            if (id = savedVoice) {
                this.dropList.Choose(idx)
                break
            }
        }

        this.guiObj.Add("Text", "y+12 x25", "Громкость диктора:")
        this.sliderNarratorVol := this.guiObj.Add("Slider", "w330 Range0-100 ToolTip y+4 x25", ttsNarrator.Volume)
        this.guiObj.Add("Text", "y+6 x25", "Скорость диктора:")
        this.sliderNarratorRate := this.guiObj.Add("Slider", "w330 Range-10-10 ToolTip y+4 x25", ttsNarrator.Rate)

        this.guiObj.SetFont("cGreen Bold")
        this.guiObj.Add("Text", "w330 Center x25 y+16", "--- ГОЛОСА ПОЛЬЗОВАТЕЛЕЙ ---")
        this.guiObj.SetFont("cDefault Norm")
        this.guiObj.Add("Text", "y+6 x25", "Громкость пользователей:")
        this.sliderUserVol := this.guiObj.Add("Slider", "w330 Range0-100 ToolTip y+4 x25", ttsUser.Volume)
        this.guiObj.Add("Text", "y+6 x25", "Скорость пользователей:")
        this.sliderUserRate := this.guiObj.Add("Slider", "w330 Range-10-10 ToolTip y+4 x25", ttsUser.Rate)

        this.guiObj.Add("Text", "x25 y+10 w330", "Не озвучивать ники (через запятую):")
        this.editIgnore := this.guiObj.Add("Edit", "w330 r2 y+4 x25", IgnoreList)

        chkState := (SkipMyMessages == 1) ? "Checked" : ""
        this.chkSkipMy := this.guiObj.Add("Checkbox", "w330 y+8 x25 " chkState, "Не озвучивать мои сообщения")

        voiceInState := (VoiceInputMode == 1) ? "Checked" : ""
        this.chkVoiceInput := this.guiObj.Add("Checkbox", "w330 y+8 x25 " voiceInState, "Включить голосовой ввод (удерживай Левый Ctrl)")

        shortcutPath := A_Startup "\CommFort_TTS.lnk"
        autoStartState := FileExist(shortcutPath) ? "Checked" : ""
        this.chkAutoStart := this.guiObj.Add("Checkbox", "w330 y+8 x25 " autoStartState, "Автоматически загружать с Windows")

        Tab.UseTab()

        ; ---------------- ВКЛАДКА 2: ПЕРСОНАЛЬНЫЕ ГОЛОСА ----------------
        Tab.UseTab(2)

        this.guiObj.Add("Text", "x25 y+15", "Выберите или введите никнейм:")
        this.comboCustomNick := this.guiObj.Add("ComboBox", "w330 y+4 x25", this.ActiveNicks)
        this.comboCustomNick.OnEvent("Change", ObjBindMethod(this, "AutoLoad"))
        this.guiObj.Add("Text", "y+12 x25", "Индивидуальный голос (Гибридный ИИ / SAPI):")
        this.dropCustomVoice := this.guiObj.Add("DropDownList", "w292 Choose1 y+4 x25", this.HybridVoicesNames)
        btnPreviewCustom := this.guiObj.Add("Button", "w34 x321 yp-1 h26", "🔊")
        btnPreviewCustom.OnEvent("Click", ObjBindMethod(this, "PreviewCustomVoice"))

        this.guiObj.SetFont("cPurple Bold")
        this.guiObj.Add("Text", "w330 Center x25 y+16", "--- ИНДИВИДУАЛЬНЫЙ МИКШЕР ---")
        this.guiObj.SetFont("cDefault Norm")
        this.guiObj.Add("Text", "x25 y+10", "Персональная громкость:")
        this.sliderCustomVol := this.guiObj.Add("Slider", "w330 Range0-100 ToolTip y+4 x25", 100)
        this.guiObj.Add("Text", "x25 y+6", "Персональная скорость:")
        this.sliderCustomRate := this.guiObj.Add("Slider", "w330 Range-10-10 ToolTip y+4 x25", 0)
        btnSaveCustom := this.guiObj.Add("Button", "w155 x25 y+15 h35", "Сохранить для ника")
        btnSaveCustom.OnEvent("Click", ObjBindMethod(this, "SaveCustom"))
        btnDeleteCustom := this.guiObj.Add("Button", "w155 x200 yp h35", "Удалить для ника")
        btnDeleteCustom.OnEvent("Click", ObjBindMethod(this, "DeleteCustom"))

        this.guiObj.SetFont("cTeal Bold")
        this.guiObj.Add("Text", "w330 Center x25 y+18", "--- МОЙ ГОЛОС ДЛЯ ДРУГИХ ---")
        this.guiObj.SetFont("cDefault Norm")

        mySharedKey := IniRead(IniFile, "MySharedVoice_" ActiveProfile, "VoiceKey", "")
        mySharedRate := IniRead(IniFile, "MySharedVoice_" ActiveProfile, "Rate", "0")
        mySharedEnabled := Integer(IniRead(IniFile, "MySharedVoice_" ActiveProfile, "Enabled", "0"))

        this.guiObj.Add("Text", "x25 y+8", "Мой голос в чате у других:")
        this.dropMySharedVoice := this.guiObj.Add("DropDownList", "w292 Choose1 y+4 x25", this.HybridVoicesNames)
        btnPreviewMyShared := this.guiObj.Add("Button", "w34 x321 yp-1 h26", "🔊")
        btnPreviewMyShared.OnEvent("Click", ObjBindMethod(this, "PreviewMySharedVoice"))

        if (mySharedKey != "") {
            for idx, id in this.HybridVoicesIds {
                if (InStr(id, mySharedKey)) {
                    this.dropMySharedVoice.Choose(idx)
                    break
                }
            }
        }

        this.guiObj.Add("Text", "x25 y+8", "Моя скорость речи:")
        this.sliderMySharedRate := this.guiObj.Add("Slider", "w330 Range-10-10 ToolTip y+4 x25", mySharedRate)

        chkSendState := (mySharedEnabled == 1) ? "Checked" : ""
        this.chkSendMyVoice := this.guiObj.Add("Checkbox", "w330 y+6 x25 " chkSendState, "Передавать мой голос при входе в чат")

        btnSaveMyShared := this.guiObj.Add("Button", "w330 x25 y+10 h35", "Сохранить мой голос в профиль")
        btnSaveMyShared.OnEvent("Click", ObjBindMethod(this, "SaveMySharedVoice"))

      dedState := (EnableDedWelcome == 1) ? "Checked" : ""
      this.chkDedWelcome := this.guiObj.Add("Checkbox", "w330 y+10 x25 " dedState, "Включить приветствие Деда Вани при входе")

        Tab.UseTab()

        ; ---------------- ВКЛАДКА 3: О ПРОГРАММЕ ----------------
        Tab.UseTab(3)

        this.guiObj.SetFont("s11 Bold cNavy")
        this.guiObj.Add("Text", "w330 Center x25 y+25", "Голосовой модуль CommFort TTS")
        this.guiObj.SetFont("s9 cGray Norm")
        this.guiObj.Add("Text", "w330 Center y+4", "Двусторонний голосовой интерфейс для чата")

        this.guiObj.SetFont("s10 cDefault Norm")
        aboutText := "Модуль обеспечивает озвучивание сообщений чата с учётом пола, "
                   . "поддержку нейросетевых голосов (Piper, Yandex Cloud), "
                   . "автоматический обмен голосовыми профилями между участниками "
                   . "и автономный голосовой ввод речи без интернета (Vosk)."
        this.guiObj.Add("Text", "w330 x25 y+20", aboutText)

        this.guiObj.SetFont("cTeal Bold")
        this.guiObj.Add("Text", "w330 Center x25 y+25", "--- РАЗРАБОТКА ---")
        this.guiObj.SetFont("s10 cDefault Norm")
        this.guiObj.Add("Text", "w330 Center x25 y+10", "Архитектура, логика и код созданы`nсовместно с ИИ-ассистентом Google (Gemini)")

        this.guiObj.SetFont("cBlue Bold")
        this.guiObj.Add("Text", "w330 Center x25 y+30", "--- СПРАВОЧНЫЕ МАТЕРИАЛЫ ---")
        this.guiObj.SetFont("s10 cDefault Norm")

        btnUserHelp := this.guiObj.Add("Button", "w330 x25 y+12 h40", "📖 Руководство пользователя")
        btnUserHelp.OnEvent("Click", ObjBindMethod(this, "OpenUserHelp"))

        btnTechDoc := this.guiObj.Add("Button", "w330 x25 y+12 h40", "⚙️ Техническая документация")
        btnTechDoc.OnEvent("Click", ObjBindMethod(this, "OpenTechDoc"))

        Tab.UseTab()

        this.guiObj.SetFont("Bold")
        btnSaveAll := this.guiObj.Add("Button", "w180 x100 y750 h40", "Сохранить всё")
        this.guiObj.SetFont("Norm")
        btnSaveAll.OnEvent("Click", ObjBindMethod(this, "SaveMain"))
        this.ToggleTtsModeFields()
        this.guiObj.Show("w380 h815")
    }

    static ToggleTtsModeFields(ctrl := "", info := "") {
        mode := this.dropTtsMode.Value
        if (mode == 1) {
            this.btnConfigureAi.Enabled := false
            this.btnConfigureAi.Text := "⚙ Недоступно"
        } else {
            this.btnConfigureAi.Enabled := true
            this.btnConfigureAi.Text := "⚙ Настроить..."
        }
    }

    static OpenAiModalWindow(ctrl := "", info := "") {
        mode := this.dropTtsMode.Value
        subGui := Gui("+AlwaysOnTop +ToolWindow +Owner" this.guiObj.Hwnd, "Параметры ИИ")
        this.guiObj.Opt("+Disabled")
        subGui.SetFont("s10", "Segoe UI")

        editPath := ""
        editKey := ""
        editFolder := ""

        if (mode == 2) {
            subGui.Add("Text", "x15 y15 w310", "Путь к папке Piper (где находится piper.exe):")
            editPath := subGui.Add("Edit", "w210 x15 y+6", this.currentLocalPath)
            btnBrowse := subGui.Add("Button", "w80 xp+220 yp-1 h28", "Обзор...")
            btnBrowse.OnEvent("Click", SelectDir)
            subGui.SetFont("Bold")
            btnOk := subGui.Add("Button", "w100 x60 y+20 h32", "Применить")
            subGui.SetFont("Norm")
            btnOk.OnEvent("Click", ApplyLocal)
            btnCancel := subGui.Add("Button", "w100 xp+120 yp h32", "Отмена")
            btnCancel.OnEvent("Click", CloseModal)
            subGui.OnEvent("Close", CloseModal)
            subGui.OnEvent("Escape", CloseModal)
            subGui.Show("w340 h135")
        } else if (mode == 3) {
            subGui.Add("Text", "x15 y15 w310", "API-ключ Yandex Cloud:")
            editKey := subGui.Add("Edit", "w310 y+6 Password", this.currentCloudKey)
            subGui.Add("Text", "x15 y+12 w310", "Folder ID Yandex:")
            editFolder := subGui.Add("Edit", "w310 y+6", this.currentCloudFolder)
            subGui.SetFont("Bold")
            btnOk := subGui.Add("Button", "w100 x60 y+20 h32", "Применить")
            subGui.SetFont("Norm")
            btnOk.OnEvent("Click", ApplyCloud)
            btnCancel := subGui.Add("Button", "w100 xp+120 yp h32", "Отмена")
            btnCancel.OnEvent("Click", CloseModal)
            subGui.OnEvent("Close", CloseModal)
            subGui.OnEvent("Escape", CloseModal)
            subGui.Show("w340 h210")
        }

        CloseModal(*) {
            try this.guiObj.Opt("-Disabled")
            subGui.Destroy()
        }
        SelectDir(*) {
            subGui.Opt("+OwnDialogs")
            startDir := DirExist(editPath.Value) ? editPath.Value : A_ScriptDir
            selDir := DirSelect("*" startDir, "1", "Выберите папку с piper.exe")
            if (selDir != "")
                editPath.Value := selDir
        }

        ApplyLocal(*) {
            global IniFile, ActiveProfile, LocalEnginePath
            this.currentLocalPath := Trim(editPath.Value)
            LocalEnginePath := this.currentLocalPath
            IniWrite(this.currentLocalPath, IniFile, ActiveProfile, "LocalEnginePath")
            this.RefreshVoiceLists(true)
            CloseModal()
        }
        ApplyCloud(*) {
            global IniFile, ActiveProfile, CloudApiKey, CloudFolderId
            this.currentCloudKey := Trim(editKey.Value)
            this.currentCloudFolder := Trim(editFolder.Value)
            CloudApiKey := this.currentCloudKey
            CloudFolderId := this.currentCloudFolder
            IniWrite(this.currentCloudKey, IniFile, ActiveProfile, "CloudApiKey")
            IniWrite(this.currentCloudFolder, IniFile, ActiveProfile, "CloudFolderId")
            CloseModal()
        }
    }

    static AutoLoad(ctrl := "", info := "") {
        global IniFile, ttsNarrator
        rawNick := Trim(this.comboCustomNick.Text)
        cleanNick := RTrim(rawNick, " *")
        if (cleanNick = "" || cleanNick = "Выберите или введите ник...")
            return

        sec := "Custom_" cleanNick
        cVoiceId := IniRead(IniFile, sec, "VoiceId", "")
        if (cVoiceId != "") {
            this.sliderCustomVol.Value := IniRead(IniFile, sec, "Volume", "100")
            this.sliderCustomRate.Value := IniRead(IniFile, sec, "Rate", "0")
            isFound := false
            for idx, id in this.HybridVoicesIds {
                if (id = cVoiceId) {
                    this.dropCustomVoice.Choose(idx)
                    isFound := true
                    break
                }
            }
            if (!isFound) {
                for idx, id in this.HybridVoicesIds {
                    if (id = "[ИИ] Авто-выбор по полу") {
                        this.dropCustomVoice.Choose(idx)
                        break
                    }
                }
            }
        } else {
            this.sliderCustomVol.Value := this.sliderUserVol.Value
            this.sliderCustomRate.Value := this.sliderUserRate.Value
            if (this.dropTtsMode.Value != 1) {
                for idx, id in this.HybridVoicesIds {
                    if (id = "[ИИ] Авто-выбор по полу") {
                        this.dropCustomVoice.Choose(idx)
                        break
                    }
                }
            } else {
                TempMaleVoices := []
                TempFemaleVoices := []
                tVoices := ttsNarrator.GetVoices()
                loop tVoices.Count {
                    v := tVoices.Item(A_Index - 1)
                    try {
                        gAttr := v.GetAttribute("Gender")
                    } catch {
                        gAttr := "Female"
                    }
                    if (gAttr = "Male")
                        TempMaleVoices.Push(v.Id)
                    else
                        TempFemaleVoices.Push(v.Id)
                }
                if (TempMaleVoices.Length = 0 && TempFemaleVoices.Length > 0)
                    TempMaleVoices := TempFemaleVoices
                if (TempFemaleVoices.Length = 0 && TempMaleVoices.Length > 0)
                    TempFemaleVoices := TempMaleVoices

                isFem := IsUserFemale(cleanNick, 0, false)
                uHash := 0
                loop Parse, cleanNick {
                    uHash += Ord(A_LoopField)
                }
                if (isFem) {
                    idx := Mod(uHash, TempFemaleVoices.Length) + 1
                    defVoiceId := TempFemaleVoices[idx]
                } else {
                    idx := Mod(uHash, TempMaleVoices.Length) + 1
                    defVoiceId := TempMaleVoices[idx]
                }
                for idx, id in this.HybridVoicesIds {
                    if (id = defVoiceId) {
                        this.dropCustomVoice.Choose(idx)
                        break
                    }
                }
            }
        }
    }

    static SaveCustom(ctrl := "", info := "") {
        global IniFile
        rawNick := Trim(this.comboCustomNick.Text)
        cleanNick := RTrim(rawNick, " *")
        if (cleanNick = "" || cleanNick = "Выберите или введите ник...") {
            MsgBox("Укажите корректный никнейм перед сохранением!", "Ошибка", 48)
            return
        }

        sec := "Custom_" cleanNick
        vIdx := this.dropCustomVoice.Value
        vId := this.HybridVoicesIds[vIdx]
        IniWrite(vId, IniFile, sec, "VoiceId")
        IniWrite(this.sliderCustomVol.Value, IniFile, sec, "Volume")
        IniWrite(this.sliderCustomRate.Value, IniFile, sec, "Rate")

        newNickWithStar := cleanNick " *"
        isAlreadyInList := false
        for idx, item in this.ActiveNicks {
            if (StrLower(RTrim(item, " *")) = StrLower(cleanNick)) {
                this.ActiveNicks[idx] := newNickWithStar
                isAlreadyInList := true
                break
            }
        }
        if (!isAlreadyInList)
            this.ActiveNicks.Push(newNickWithStar)

        this.comboCustomNick.Delete()
        this.comboCustomNick.Add(this.ActiveNicks)
        this.comboCustomNick.Text := newNickWithStar
        MsgBox("Персональные настройки для '" cleanNick "' успешно сохранены!", "Готово", "0x40040")
    }

    static DeleteCustom(ctrl := "", info := "") {
        global IniFile
        rawNick := Trim(this.comboCustomNick.Text)
        cleanNick := RTrim(rawNick, " *")
        if (cleanNick = "" || cleanNick = "Выберите или введите ник...") {
            MsgBox("Выберите корректный никнейм для удаления!", "Ошибка", 48)
            return
        }

        sec := "Custom_" cleanNick
        try IniDelete(IniFile, sec)

        for idx, item in this.ActiveNicks {
            if (StrLower(RTrim(item, " *")) = StrLower(cleanNick)) {
                this.ActiveNicks[idx] := cleanNick
                break
            }
        }
        this.comboCustomNick.Delete()
        this.comboCustomNick.Add(this.ActiveNicks)
        this.comboCustomNick.Text := cleanNick
        this.AutoLoad()
        MsgBox("Персональные настройки для '" cleanNick "' успешно удалены.", "Успешно", "0x40040")
    }

    static PreviewNarratorVoice(ctrl := "", info := "") {
        idx := this.dropList.Value
        if (idx < 1 || idx > this.NarratorVoicesIds.Length)
            return
        voiceId := this.NarratorVoicesIds[idx]
        vol := this.sliderNarratorVol.Value
        rate := this.sliderNarratorRate.Value
        SpeakByVoiceId("Раз, два, три. Вот так звучит голос диктора в чате.", voiceId, false, true, vol, rate)
    }

    static PreviewCustomVoice(ctrl := "", info := "") {
        global LastAuthor
        idx := this.dropCustomVoice.Value
        if (idx < 1 || idx > this.HybridVoicesIds.Length)
            return
        voiceId := this.HybridVoicesIds[idx]
        vol := this.sliderCustomVol.Value
        rate := this.sliderCustomRate.Value

        rawNick := Trim(this.comboCustomNick.Text)
        cleanNick := RTrim(rawNick, " *")
        isFem := (cleanNick != "") ? IsUserFemale(cleanNick, 0, false) : false

        oldAuthor := LastAuthor
        if (cleanNick != "")
            LastAuthor := cleanNick

        SpeakByVoiceId("Раз, два, три. Вот так звучит этот голос на кордоне.", voiceId, isFem, false, vol, rate)
        LastAuthor := oldAuthor
    }

    static PreviewMySharedVoice(ctrl := "", info := "") {
        idx := this.dropMySharedVoice.Value
        if (idx < 1 || idx > this.HybridVoicesIds.Length)
            return
        voiceId := this.HybridVoicesIds[idx]
        vol := this.sliderUserVol.Value
        rate := this.sliderMySharedRate.Value
        SpeakByVoiceId("Раз, два, три. Так меня будут слышать в чате.", voiceId, false, false, vol, rate)
    }

    static SaveMySharedVoice(ctrl := "", info := "") {
        global IniFile, ActiveProfile, BaseConfigDir
        idx := this.dropMySharedVoice.Value
        if (idx < 1 || idx > this.HybridVoicesIds.Length)
            return

        fullId := this.HybridVoicesIds[idx]
        fullName := this.HybridVoicesNames[idx]
        rateVal := this.sliderMySharedRate.Value
        isEnabled := this.chkSendMyVoice.Value

        voiceKey := fullName
        if (InStr(fullName, " (SAPI)")) {
            cleanDesc := StrReplace(fullName, " (SAPI)", "")
            if RegExMatch(cleanDesc, "i)(Aleksandr|Irina|Elena|Yuri|Milena|Katya|Nikolay|Maxim|Alyona|Philipp|Pavel|Anna|Boris)", &m)
                voiceKey := m[1]
            else
                voiceKey := cleanDesc
        }

        sec := "MySharedVoice_" ActiveProfile
        IniWrite(voiceKey, IniFile, sec, "VoiceKey")
        IniWrite(fullId, IniFile, sec, "FullId")
        IniWrite(rateVal, IniFile, sec, "Rate")
        IniWrite(isEnabled, IniFile, sec, "Enabled")

        accountDataIni := BaseConfigDir "\Accounts\" ActiveProfile "\data.ini"
        if FileExist(accountDataIni) {
            try {
                tagStr := "[TTS:" voiceKey "|" rateVal "]"
                currentNotes := IniRead(accountDataIni, "Account", "Notes", "")
                cleanNotes := Trim(RegExReplace(currentNotes, "\s*\[TTS:[^\]]+\]", ""))
                newNotes := (cleanNotes != "") ? (cleanNotes " " tagStr) : tagStr
                IniWrite(newNotes, accountDataIni, "Account", "Notes")
            }
        }

        MsgBox("Ваш сетевой голос '" voiceKey "' сохранён в настройки и профиль CommFort!", "Готово", "0x40040")
    }

    static OpenUserHelp(ctrl := "", info := "") {
        helpFile := A_ScriptDir "\Help_User.html"
        if FileExist(helpFile)
            Run('"' helpFile '"')
        else
            MsgBox("Файл руководства пользователя пока не создан:`n" helpFile, "Справка", 64)
    }

    static OpenTechDoc(ctrl := "", info := "") {
        docFile := A_ScriptDir "\Help_Dev.html"
        if FileExist(docFile)
            Run('"' docFile '"')
        else
            MsgBox("Файл технической документации пока не создан:`n" docFile, "Документация", 64)
    }

    static SaveMain(ctrl := "", info := "") {
        global IniFile, ttsNarrator, ttsUser, TargetChannel, IgnoreList, SkipMyMessages, LogFile, BaseLogDir, ActiveProfile, lastPos, VoiceInputMode, TtsMode

        chosenIndex := this.dropList.Value
        chosenId := this.NarratorVoicesIds[chosenIndex]
        nVol := this.sliderNarratorVol.Value
        nRate := this.sliderNarratorRate.Value
        uVol := this.sliderUserVol.Value
        uRate := this.sliderUserRate.Value
        ignoreVal := Trim(this.editIgnore.Value)
        skipVal := this.chkSkipMy.Value
        voiceInVal := this.chkVoiceInput.Value
        newChannel := this.dropChannel.Text
        newTtsMode := this.dropTtsMode.Value

IniWrite(newChannel, IniFile, ActiveProfile, "TargetChannel")
IniWrite(chosenId, IniFile, ActiveProfile, "NarratorVoiceId")
IniWrite(nVol, IniFile, ActiveProfile, "NarratorVolume")
IniWrite(nRate, IniFile, ActiveProfile, "NarratorRate")
IniWrite(uVol, IniFile, ActiveProfile, "UserVolume")
IniWrite(uRate, IniFile, ActiveProfile, "UserRate")
IniWrite(ignoreVal, IniFile, ActiveProfile, "IgnoreList")
IniWrite(skipVal, IniFile, ActiveProfile, "SkipMyMessages")
IniWrite(voiceInVal, IniFile, ActiveProfile, "VoiceInputMode")
IniWrite(newTtsMode, IniFile, ActiveProfile, "TtsMode")
IniWrite(this.currentLocalPath, IniFile, ActiveProfile, "LocalEnginePath")
IniWrite(this.currentCloudKey, IniFile, ActiveProfile, "CloudApiKey")
IniWrite(this.currentCloudFolder, IniFile, ActiveProfile, "CloudFolderId")
TargetChannel := newChannel
TtsMode := newTtsMode
ttsNarrator.Volume := nVol
ttsNarrator.Rate := nRate
ttsUser.Volume := uVol
ttsUser.Rate := uRate
IgnoreList := ignoreVal
SkipMyMessages := skipVal
      global EnableDedWelcome
      dedVal := this.chkDedWelcome.Value
      IniWrite(dedVal, IniFile, ActiveProfile, "EnableDedWelcome")
      EnableDedWelcome := dedVal

VoiceInputMode := voiceInVal
; Если включён голосовой ввод — прогреваем модель Vosk в памяти заранее
if (VoiceInputMode == 1)
InitVoskEngine()
shortcutPath := A_Startup "\CommFort_TTS.lnk"
if (this.chkAutoStart.Value == 1) {
FileCreateShortcut(A_ScriptFullPath, shortcutPath, A_ScriptDir, "", "Голосовой модуль CommFort TTS")
} else if FileExist(shortcutPath) {
try FileDelete(shortcutPath)
}
CurrentMonthDir := FormatTime(, "yyyy_MM")
LogFile := BaseLogDir "" ActiveProfile "" CurrentMonthDir "\Channels" TargetChannel ".cflog"
if FileExist(LogFile) {
try {
f := FileOpen(LogFile, "r-d")
lastPos := f.Length
f.Close()
}
} else {
lastPos := 0
}
this.guiObj.Destroy()
this.guiObj := ""
SpeakByVoiceId("Все настройки сохранены.", chosenId, false, true, nVol, nRate)
}
}
; ================================================================
; ГОЛОСОВОЙ ВВОД ПО УДЕРЖАНИЮ ЛЕВОГО CTRL (VOSK / WINDOWS)
; ================================================================
A_MaxHotkeysPerInterval := 500
#HotIf (!isVoiceRecBusy && VoiceInputMode == 1 && ProcessExist("CommFort.exe"))
~LCtrl:: {
global isVoiceRecBusy
isVoiceRecBusy := true
SetTimer(HandleVoiceInputSession, -10)
}
#HotIf
HandleVoiceInputSession() {
global isVoiceRecBusy, voskModelPtr, voskDllLoaded
try {
; Ждём 250 мс: если клавишу отпустили быстро или нажали Ctrl+C / Ctrl+V — выходим без записи
startTick := A_TickCount
while (A_TickCount - startTick < 250) {
if !GetKeyState("LCtrl", "P")
return
if (A_PriorKey != "LControl")
return
Sleep(20)
}
if WinExist("ahk_exe CommFort.exe") && !WinActive("ahk_exe CommFort.exe") {
WinActivate("ahk_exe CommFort.exe")
WinWaitActive("ahk_exe CommFort.exe", , 1)
Sleep(80)
}
; Страховка: если движок Vosk ещё не был прогрет при старте — пробуем загрузить сейчас
if (!voskDllLoaded)
InitVoskEngine()
if (voskDllLoaded && voskModelPtr) {
wavFile := A_Temp "\cf_voice_vosk.wav"
try FileDelete(wavFile)
DllCall("winmm\mciSendStringW", "Str", "close cf_rec", "Ptr", 0, "UInt", 0, "Ptr", 0)
DllCall("winmm\mciSendStringW", "Str", "open new type waveaudio alias cf_rec", "Ptr", 0, "UInt", 0, "Ptr", 0)
DllCall("winmm\mciSendStringW", "Str", "set cf_rec format tag pcm", "Ptr", 0, "UInt", 0, "Ptr", 0)
DllCall("winmm\mciSendStringW", "Str", "set cf_rec channels 1", "Ptr", 0, "UInt", 0, "Ptr", 0)
DllCall("winmm\mciSendStringW", "Str", "set cf_rec samplespersec 16000", "Ptr", 0, "UInt", 0, "Ptr", 0)
DllCall("winmm\mciSendStringW", "Str", "set cf_rec bitspersample 16", "Ptr", 0, "UInt", 0, "Ptr", 0)
SoundBeep(850, 90)
DllCall("winmm\mciSendStringW", "Str", "record cf_rec", "Ptr", 0, "UInt", 0, "Ptr", 0)
recStart := A_TickCount
while GetKeyState("LCtrl", "P") && (A_TickCount - recStart < 20000) {
Sleep(30)
}
DllCall("winmm\mciSendStringW", "Str", "stop cf_rec", "Ptr", 0, "UInt", 0, "Ptr", 0)
DllCall("winmm\mciSendStringW", "Str", 'save cf_rec "' wavFile '"', "Ptr", 0, "UInt", 0, "Ptr", 0)
DllCall("winmm\mciSendStringW", "Str", "close cf_rec", "Ptr", 0, "UInt", 0, "Ptr", 0)
SoundBeep(550, 90)
if FileExist(wavFile) {
f := FileOpen(wavFile, "r")
fSize := f.Length
if (fSize > 44) {
pcmSize := fSize - 44
pcmBuf := Buffer(pcmSize)
f.Seek(44, 0)
f.RawRead(pcmBuf, pcmSize)
f.Close()
recPtr := DllCall("libvosk\vosk_recognizer_new", "Ptr", voskModelPtr, "Float", 16000.0, "Ptr")
if (recPtr) {
DllCall("libvosk\vosk_recognizer_accept_waveform", "Ptr", recPtr, "Ptr", pcmBuf, "Int", pcmSize, "Int")
resJsonPtr := DllCall("libvosk\vosk_recognizer_final_result", "Ptr", recPtr, "Ptr")
resJson := StrGet(resJsonPtr, "UTF-8")
DllCall("libvosk\vosk_recognizer_free", "Ptr", recPtr, "Int")
cleanText := ""
if RegExMatch(resJson, '"text"\s*:\s*"([^"]*)"', &m)
cleanText := Trim(m)
if (cleanText != "") {
firstChar := StrUpper(SubStr(cleanText, 1, 1))
cleanText := firstChar SubStr(cleanText, 2)
if WinExist("ahk_exe CommFort.exe") {
WinActivate("ahk_exe CommFort.exe")
WinWaitActive("ahk_exe CommFort.exe", , 1)
}
savedClip := ClipboardAll()
A_Clipboard := cleanText
if ClipWait(1) {
Send("^v")
Sleep(80)
Send("{Enter}")
}
Sleep(100)
A_Clipboard := savedClip
}
}
} else {
f.Close()
}
}
try FileDelete(wavFile)
} else {
; Резервная диктовка Windows (Win + H), если папка vosk отсутствует
SoundBeep(850, 90)
Send("#h")
while GetKeyState("LCtrl", "P") {
Sleep(30)
}
Send("#h")
Sleep(300)
Send("{Esc}")
Sleep(100)
Send("{Enter}")
SoundBeep(550, 90)
}
} catch as e {
LogError("VoiceInput_LCtrl", e)
} finally {
isVoiceRecBusy := false
}
}