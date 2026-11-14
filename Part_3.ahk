; ================================================================
; ЧАСТЬ 3 ИЗ 4: ОСНОВНОЙ ДЕКОДЕР ЛОГОВ, ФИЛЬТРЫ И ДВИЖКИ СИНТЕЗА ИИ
; ================================================================
ParseBinaryLog() {
    global lastPos, ttsNarrator, ttsUser, LogFile, BaseLogDir, TargetChannel, isEngineReady
    global LastAuthor, LastAuthorGender, IgnoreList, isMuted, ActiveProfile, SkipMyMessages, IniFile
    global TtsMode
    static isBusy := false

    if (!isEngineReady || isBusy)
        return

    isBusy := true
    try {
        CurrentMonthDir := FormatTime(, "yyyy_MM")
        expectedLogFile := BaseLogDir "\" ActiveProfile "\" CurrentMonthDir "\Channels\" TargetChannel ".cflog"
        if (StrLower(LogFile) != StrLower(expectedLogFile)) {
            LogFile := expectedLogFile
            if FileExist(LogFile) {
                try {
                    f := FileOpen(LogFile, "r-d")
                    lastPos := f.Length
                    f.Close()
                }
            } else {
                lastPos := 0
            }
        }

        if (!FileExist(LogFile))
            return

        fileObj := FileOpen(LogFile, "r-d")
        fileObj.Seek(0, 2)
        currentLength := fileObj.Pos

        if (currentLength < lastPos)
            lastPos := 0

        if (currentLength = lastPos) {
            fileObj.Close()
            return
        }

        bytesToRead := currentLength - lastPos
        fileObj.Seek(lastPos, 0)
        buf := Buffer(bytesToRead)
        actualRead := fileObj.RawRead(buf)
        fileObj.Close()

        if (actualRead <= 0)
            return

        LoadProfileSettings()
        narratorVoiceId := IniRead(IniFile, ActiveProfile, "NarratorVoiceId", "")

        LocalMaleVoices := []
        LocalFemaleVoices := []
        allVoices := ttsNarrator.GetVoices()
        loop allVoices.Count {
            v := allVoices.Item(A_Index - 1)
            try {
                genderAttr := v.GetAttribute("Gender")
            } catch {
                genderAttr := "Female"
            }
            if (genderAttr = "Male")
                LocalMaleVoices.Push(v.Id)
            else
                LocalFemaleVoices.Push(v.Id)
        }
        if (LocalMaleVoices.Length = 0 && LocalFemaleVoices.Length > 0)
            LocalMaleVoices := LocalFemaleVoices
        if (LocalFemaleVoices.Length = 0 && LocalMaleVoices.Length > 0)
            LocalFemaleVoices := LocalMaleVoices

        offset := 0
        while (offset < actualRead) {
            if (NumGet(buf, offset, "UChar") != 188) {
                offset += 1
                continue
            }

            if (offset + 4 > actualRead)
                break

            blockLength := NumGet(buf, offset + 1, "UShort") + (NumGet(buf, offset + 3, "UChar") << 16)
            if (blockLength <= 0) {
                offset += 1
                continue
            }

            if (offset + 4 + blockLength > actualRead)
                break

            dataOffset := offset + 4 + 8

            if (dataOffset < offset + 4 + blockLength) {
                msgType := NumGet(buf, dataOffset, "UChar")

                if (msgType = 110) {
                    dataOffset += 1
                    genderByte := NumGet(buf, dataOffset, "UChar")
                    dataOffset += 1
                    nameLen := NumGet(buf, dataOffset, "UChar")
                    dataOffset += 1
                    author := StrGet(buf.Ptr + dataOffset, nameLen, "UTF-16")
                    dataOffset += (nameLen * 2) + 4
                    textLen := NumGet(buf, dataOffset, "UShort") + (NumGet(buf, dataOffset + 2, "UChar") << 16)
                    dataOffset += 3

                    if (author != "" && textLen > 0 && !isMuted) {
                        isSelf := (SkipMyMessages == 1 && StrLower(Trim(author)) = StrLower(Trim(ActiveProfile)))
                        isIgnored := false
                        loop Parse, IgnoreList, "," {
                            if (StrLower(Trim(author)) = StrLower(Trim(A_LoopField))) {
                                isIgnored := true
                                break
                            }
                        }

                        if (!isSelf && !isIgnored) {
                            message := StrGet(buf.Ptr + dataOffset, textLen, "UTF-16")
                            message := ExtractAndSaveSharedVoice(author, message)

                            tempCheck := RegExReplace(message, "[\x{0000}-\x{001F}]", "")
                            if (Trim(tempCheck) != "") {
                                LastAuthor := author
                                LastAuthorGender := genderByte
                                message := FilterBadWords(message)
                                message := ProcessSmileys(message)

                                if (StrLower(Trim(author)) != "дед ваня") {
                                    SpeakByVoiceId("Пишет " author, narratorVoiceId, false, true, ttsNarrator.Volume, ttsNarrator.Rate)
                                }

                                isFemale := IsUserFemale(author, genderByte, true)

                                customSec := "Custom_" author
                                customVoiceId := IniRead(IniFile, customSec, "VoiceId", "")
                                customVol := IniRead(IniFile, customSec, "Volume", "")
                                customRate := IniRead(IniFile, customSec, "Rate", "")

                                sharedSec := "Shared_" author
                                sharedVoiceKey := IniRead(IniFile, sharedSec, "VoiceKey", "")
                                sharedRate := IniRead(IniFile, sharedSec, "Rate", "")

                                ; 1-Й ПРИОРИТЕТ: личная настройка слушателя [Custom_Ник]
                                if (customVoiceId != "" && customVoiceId != "[ИИ] Авто-выбор по полу") {
                                    activeVol := (customVol != "") ? Integer(customVol) : Integer(ttsUser.Volume)
                                    activeRate := (customRate != "") ? Integer(customRate) : Integer(ttsUser.Rate)
                                    SpeakByVoiceId(message, customVoiceId, isFemale, false, activeVol, activeRate)
                                    LoadProfileSettings()
                                }
                                ; 2-Й ПРИОРИТЕТ: сетевой профиль отправителя [Shared_Ник]
                                else if (sharedVoiceKey != "") {
                                    resolvedVoiceId := ResolveSharedVoiceId(sharedVoiceKey, isFemale)
                                    activeVol := Integer(ttsUser.Volume)
                                    activeRate := (sharedRate != "") ? Integer(sharedRate) : Integer(ttsUser.Rate)
                                    SpeakByVoiceId(message, resolvedVoiceId, isFemale, false, activeVol, activeRate)
                                    LoadProfileSettings()
                                }
                                ; 3-Й ПРИОРИТЕТ: автоподбор скрипта по полу и хешу
                                else {
                                    activeVol := Integer(ttsUser.Volume)
                                    activeRate := Integer(ttsUser.Rate)
                                    if (TtsMode == 1) {
                                        hash := 0
                                        loop Parse, author {
                                            hash += Ord(A_LoopField)
                                        }
                                        if (isFemale) {
                                            index := Mod(hash, LocalFemaleVoices.Length) + 1
                                            chosenVoiceId := LocalFemaleVoices[index]
                                        } else {
                                            index := Mod(hash, LocalMaleVoices.Length) + 1
                                            chosenVoiceId := LocalMaleVoices[index]
                                        }
                                        SpeakByVoiceId(message, chosenVoiceId, isFemale, false, activeVol, activeRate)
                                    } else if (TtsMode == 2) {
                                        SpeakLocalAi(message, isFemale, "", activeVol, activeRate)
                                    } else if (TtsMode == 3) {
                                        SpeakCloudAi(message, isFemale, "", activeVol, activeRate)
                                    }
                                }
                            }
                        }
                    }
                } else if (msgType = 111) {
                    dataOffset += 1
                    iconByte := NumGet(buf, dataOffset, "UChar")
                    dataOffset += 1
                    nameLen := NumGet(buf, dataOffset, "UChar")
                    dataOffset += 1
                    imgAuthor := StrGet(buf.Ptr + dataOffset, nameLen, "UTF-16")

                    if (imgAuthor != "" && !isMuted) {
                        isSelf := (SkipMyMessages == 1 && StrLower(Trim(imgAuthor)) = StrLower(Trim(ActiveProfile)))
                        isIgnored := false
                        loop Parse, IgnoreList, "," {
                            if (StrLower(Trim(imgAuthor)) = StrLower(Trim(A_LoopField))) {
                                isIgnored := true
                                break
                            }
                        }

                        if (!isSelf && !isIgnored) {
                            LastAuthor := imgAuthor
                            nameLower := StrLower(Trim(imgAuthor))

                            if (nameLower = "дед ваня") {
                                dedImgPhrases := [
                                    "Погляди милок чего я тут нарисовал.",
"Глянь на карточку с кордона.",
"Принимай голубчик лесную открытку.",
"Эка картинка вышла любо дорого поглядеть."
]
randIdx := Random(1, dedImgPhrases.Length)
SpeakByVoiceId(dedImgPhrases[randIdx], "", false, false, ttsUser.Volume, ttsUser.Rate)
} else {
isFemale := IsUserFemale(imgAuthor, iconByte, true)
verb := isFemale ? " отправила картинку" : " отправил картинку"
SpeakByVoiceId(imgAuthor verb, narratorVoiceId, false, true, ttsNarrator.Volume, ttsNarrator.Rate)
}
}
}
} else if (msgType = 112 || msgType = 115) {
dataOffset += 1
sysTextLen := NumGet(buf, dataOffset, "UShort") + (NumGet(buf, dataOffset + 2, "UChar") << 16)
dataOffset += 3
sysMessage := StrGet(buf.Ptr + dataOffset, sysTextLen, "UTF-16")
if (sysMessage != "" && !isMuted) {
sysClean := Trim(sysMessage)
if (InStr(sysClean, "переключился в состояние")
|| InStr(sysClean, "вернулся в обычное состояние")
|| InStr(sysClean, "отменил ограничение")) {
; Пропускаем смену статусов молча
} else if (InStr(sysClean, "запретил публикацию")) {
banPhrases := [
"Вот так-то. Не балуй на кордоне, правила для всех одни.",
"Посиди, остынь малость, мил человек. Порядок в лесу нужен.",
"Егерь всё видит. Будешь знать, как на кордоне шуметь."
]
randIdx := Random(1, banPhrases.Length)
oldAuthor := LastAuthor
LastAuthor := "Дед Ваня"
SpeakByVoiceId(banPhrases[randIdx], "", false, false, ttsUser.Volume, ttsUser.Rate)
LastAuthor := oldAuthor
} else {
sysMessage := FilterBadWords(sysMessage)
sysMessage := ProcessSmileys(sysMessage)
SpeakByVoiceId(sysMessage, narratorVoiceId, false, true, ttsNarrator.Volume, ttsNarrator.Rate)
}
}
}
}
offset += 4 + blockLength
}
lastPos += offset
} catch as e {
LogError("ParseBinaryLog", e)
} finally {
isBusy := false
}
}
SpeakByVoiceId(text, voiceId, isFemale := false, isNarrator := false, vol := 100, rate := 0) {
    global ttsNarrator, ttsUser, TtsMode, LastAuthor

    isDedVanya := (!isNarrator && (StrLower(Trim(LastAuthor)) = "дед ваня"))
    foundYuri := ""
    foundAleksandr := ""

    if (isDedVanya) {
        allVoices := ttsUser.GetVoices()
        loop allVoices.Count {
            v := allVoices.Item(A_Index - 1)
            desc := v.GetDescription()
            id := v.Id
            if (InStr(desc, "Yuri") || InStr(id, "Yuri")) {
                foundYuri := id
                break
            }
            if (InStr(desc, "Aleksandr") || InStr(id, "Aleksandr")) {
                foundAleksandr := id
            }
        }
        if (foundYuri != "")
            voiceId := foundYuri
        else if (foundAleksandr != "")
            voiceId := foundAleksandr
    }

    if (voiceId = "[ИИ] Авто-выбор по полу") {
        if (TtsMode == 3)
            SpeakCloudAi(text, isFemale, "", vol, rate)
        else
            SpeakLocalAi(text, isFemale, "", vol, rate)
        return
    }
    if (SubStr(voiceId, 1, 8) = "[Piper] ") {
        modelFile := SubStr(voiceId, 9)
        SpeakLocalAi(text, isFemale, modelFile, vol, rate)
        return
    }
    if (SubStr(voiceId, 1, 9) = "[Yandex] ") {
        charName := SubStr(voiceId, 10)
        SpeakCloudAi(text, isFemale, charName, vol, rate)
        return
    }

    engine := isNarrator ? ttsNarrator : ttsUser
    if (voiceId != "") {
        allVoices := engine.GetVoices()
        loop allVoices.Count {
            v := allVoices.Item(A_Index - 1)
            if (v.Id = voiceId) {
                engine.Voice := v
                break
            }
        }
    }

    engine.Volume := vol
    engine.Rate := rate

    if (isDedVanya) {
        engine.Rate := 0

        safeText := StrReplace(text, "&", "&amp;")
        safeText := StrReplace(safeText, "<", "&lt;")
        safeText := StrReplace(safeText, ">", "&gt;")
        safeText := StrReplace(safeText, "...", ", ")
        safeText := StrReplace(safeText, " — ", ", ")

        if (foundYuri != "") {
            ssmlText := '<pitch absmiddle="-3"><rate absspeed="-3">' safeText '</rate></pitch>'
            Sleep(100)
        } else {
            ssmlText := '<pitch absmiddle="-4"><rate absmiddle="-1">' safeText '</rate></pitch>'
        }
        engine.Speak(ssmlText, 9)
    } else {
        engine.Speak(text, 1)
    }

    while (engine.Status.RunningState != 1) {
        Sleep(50)
    }
}

SpeakLocalAi(message, isFemale, specificModel := "", vol := 100, rate := 0) {
    global LocalEnginePath, LocalMaleVoiceModel, LocalFemaleVoiceModel
    slash := Chr(92)
    cleanDir := RTrim(LocalEnginePath, slash)
    piperExe := cleanDir slash "piper.exe"
    if !FileExist(piperExe) {
        LogError("SpeakLocalAi", "Не найден piper.exe: " piperExe)
        return
    }

    if (specificModel != "") {
        modelFile := specificModel
    } else {
        modelFile := isFemale ? LocalFemaleVoiceModel : LocalMaleVoiceModel
        if !FileExist(cleanDir slash modelFile) {
            loop Files, cleanDir slash "*.onnx" {
                modelFile := A_LoopFileName
                break
            }
        }
    }

    modelPath := cleanDir slash modelFile
    if !FileExist(modelPath) {
        LogError("SpeakLocalAi", "Не найдена модель голоса: " modelPath)
        return
    }

    lengthScale := Format("{:.2f}", 1.0 - (rate * 0.05))
    tempWav := A_Temp slash "tts_chat.wav"
    tempTxt := A_Temp slash "tts_input.txt"
    if FileExist(tempWav)
        FileDelete(tempWav)
    if FileExist(tempTxt)
        FileDelete(tempTxt)

    FileAppend(message, tempTxt, "UTF-8-RAW")
    cmdStr := 'cmd.exe /q /c ""' piperExe '" --model "' modelPath '" --length_scale ' lengthScale ' --output_file "' tempWav '" < "' tempTxt '""'
    RunWait(cmdStr, cleanDir, "Hide")

    if FileExist(tempWav) {
        PlayWavWithVolume(tempWav, vol)
    } else {
        LogError("SpeakLocalAi", "Piper не сгенерировал WAV-файл.")
    }
}

SpeakCloudAi(message, isFemale, specificChar := "", vol := 100, rate := 0) {
    global CloudApiKey, CloudFolderId, CloudMaleVoiceCharacter, CloudFemaleVoiceCharacter
    if (CloudApiKey = "")
        return

    voiceChar := (specificChar != "") ? specificChar : (isFemale ? CloudFemaleVoiceCharacter : CloudMaleVoiceCharacter)
    yandexSpeed := Format("{:.2f}", 1.0 + (rate * 0.05))
    tempWav := A_Temp "\tts_cloud.wav"
    if FileExist(tempWav)
        FileDelete(tempWav)

    try {
        whr := ComObject("MSXML2.ServerXMLHTTP.6.0")
        url := "https://yandex.net"
        whr.Open("POST", url, true)
        whr.SetRequestHeader("Authorization", "Api-Key " CloudApiKey)
        whr.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        body := "text=" UriEncode(message) "&voice=" voiceChar "&speed=" yandexSpeed "&folderId=" CloudFolderId "&format=lpcm&sampleRateHertz=16000"
        whr.Send(body)
        whr.WaitForResponse(10)

        if (whr.Status = 200) {
            respArr := whr.ResponseBody
            size := respArr.MaxIndex() + 1
            file := FileOpen(tempWav, "w")
            file.WriteUInt(0x46464952)
            file.WriteUInt(size + 36)
            file.WriteUInt(0x45564157)
            file.WriteUInt(0x20746d66)
            file.WriteUInt(16)
            file.WriteUShort(1)
            file.WriteUShort(1)
            file.WriteUInt(16000)
            file.WriteUInt(32000)
            file.WriteUShort(2)
            file.WriteUShort(16)
            file.WriteUInt(0x61746164)
            file.WriteUInt(size)
            VarSetStrCapacity(&dataPtr, size)
            DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(respArr), "Ptr*", &dataPtr)
            file.RawWrite(dataPtr, size)
            DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(respArr))
            file.Close()
            PlayWavWithVolume(tempWav, vol)
        } else {
            LogError("SpeakCloudAi", "HTTP статус " whr.Status ": " whr.ResponseText)
        }
    } catch as e {
        LogError("SpeakCloudAi", e)
    }
}
PlayWavWithVolume(filePath, volPercent := 100) {
    if (volPercent <= 0)
        return
    mciVol := Integer(volPercent * 10)
    if (mciVol > 1000)
        mciVol := 1000

    DllCall("winmm\mciSendStringW", "Str", "close tts_audio", "Ptr", 0, "UInt", 0, "Ptr", 0)
    err := DllCall("winmm\mciSendStringW", "Str", 'open "' filePath '" type waveaudio alias tts_audio', "Ptr", 0, "UInt", 0, "Ptr", 0)
    if (err = 0) {
        DllCall("winmm\mciSendStringW", "Str", "setaudio tts_audio volume to " mciVol, "Ptr", 0, "UInt", 0, "Ptr", 0)
        DllCall("winmm\mciSendStringW", "Str", "play tts_audio", "Ptr", 0, "UInt", 0, "Ptr", 0)

        statusBuf := Buffer(64, 0)
        loop {
            Sleep(50)
            DllCall("winmm\mciSendStringW", "Str", "status tts_audio mode", "Ptr", statusBuf, "UInt", 32, "Ptr", 0)
            if (StrGet(statusBuf) != "playing")
                break
        }
        DllCall("winmm\mciSendStringW", "Str", "close tts_audio", "Ptr", 0, "UInt", 0, "Ptr", 0)
    } else {
        SoundPlay(filePath, "Wait")
    }
}

UriEncode(str) {
    buf := Buffer(StrPut(str, "UTF-8") - 1)
    StrPut(str, buf, "UTF-8")
    encoded := ""
    loop buf.Size {
        byte := NumGet(buf, A_Index - 1, "UChar")
        if ((byte >= 0x30 && byte <= 0x39)
        || (byte >= 0x41 && byte <= 0x5A)
        || (byte >= 0x61 && byte <= 0x7A)
        || byte = 0x2D || byte = 0x2E || byte = 0x5F || byte = 0x7E) {
            encoded .= Chr(byte)
        } else {
            encoded .= Format("%{:02X}", byte)
        }
    }
    return encoded
}

FilterBadWords(text) {
    global MatWords
    cleaned := text
    for word in MatWords {
        pattern := "i)[a-zа-яё]" word "[a-zа-яё]"
        cleaned := RegExReplace(cleaned, pattern, "[пик]")
    }
    return cleaned
}

ProcessSmileys(text) {
    global SmileyDict
    processed := text
    for code, replacement in SmileyDict {
        processed := RegExReplace(processed, "i):" code ":", replacement)
    }
    processed := RegExReplace(processed, ":[A-Za-z0-9_-]+:", "")
    return processed
}

IsUserFemale(username, rawCode := 0, isFromLog := true) {
    nameLower := StrLower(Trim(username))
    if (nameLower = "")
        return false

    if (isFromLog) {
        if (rawCode == 2)
            return true
        if (rawCode == 1)
            return false
    } else {
        if (rawCode == 1)
            return true
    }

    maleExceptions := "никита,илья,саша,паша,миша,лева,лёва,данила,ваня,женя,валя,слава,коля,толя,витя,петя,серёжа,сережа,лёша,леша,стёпа,степа,юра,гена,дима,рома,тёма,тема,кузьма,фома,лука,даня,сеня,боря,жора,гоша,кеша,гриша,митя,веня,федя,филя,шура"
    loop Parse, maleExceptions, "," {
        ex := Trim(A_LoopField)
        if (nameLower = ex || RegExMatch(nameLower, "[\s_-]" ex "$"))
            return false
    }

    lastChar := SubStr(nameLower, -1)
    return (lastChar = "а" || lastChar = "я")
}

ExtractAndSaveSharedVoice(author, rawMsg) {
    global IniFile
    cleanMsg := rawMsg

    if RegExMatch(cleanMsg, 'i)\[url="tts:([^|\]]+)\|([^\]]+)"\](.*?)\[/url\]', &m) {
        vKey := Trim(m[1])
        vRate := Trim(m[2])

        if (vKey != "" && author != "") {
            sec := "Shared_" Trim(author)
            IniWrite(vKey, IniFile, sec, "VoiceKey")
            IniWrite(vRate, IniFile, sec, "Rate")
        }

        cleanMsg := RegExReplace(cleanMsg, 'i)\[url="tts:[^"]+"\](.*?)\[/url\]', "$1")
    }
    return cleanMsg
}

ResolveSharedVoiceId(voiceKey, isFemale := false) {
    global ttsUser, TtsMode

    if (SubStr(voiceKey, 1, 8) = "[Piper] " || SubStr(voiceKey, 1, 9) = "[Yandex] " || voiceKey = "[ИИ] Авто-выбор по полу")
        return voiceKey

    allVoices := ttsUser.GetVoices()
    loop allVoices.Count {
        v := allVoices.Item(A_Index - 1)
        if (InStr(v.GetDescription(), voiceKey) || InStr(v.Id, voiceKey))
            return v.Id
    }

    if (TtsMode != 1)
        return "[ИИ] Авто-выбор по полу"

    loop allVoices.Count {
        v := allVoices.Item(A_Index - 1)
        try {
            g := v.GetAttribute("Gender")
        } catch {
            g := "Female"
        }
        if ((isFemale && g = "Female") || (!isFemale && g = "Male"))
            return v.Id
    }
    return ""
}
