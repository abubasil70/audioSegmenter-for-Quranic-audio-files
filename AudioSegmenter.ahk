#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; إعدادات المسارات والمتغيرات العامة
; ==============================================================================
Global CSV_FilePath := A_ScriptDir "\quran.csv"
Global Ini_File     := A_ScriptDir "\setting.ini"
Global Py_Script    := A_ScriptDir "\slicer.py"
Global Output_Dir   := A_ScriptDir "\Ayahs_Output"
Global Log_File := A_ScriptDir "\log.txt"


; متغيرات العمل
Global QuranData      := Map() 
Global CurrentSuraID  := 1
Global CurrentAyahNum := 1
Global LastTimestamp  := 0
Global FullAudioPath  := ""
Global VerseText      := ""

; إنشاء مجلد المخرجات
if !DirExist(Output_Dir)
    DirCreate Output_Dir

; تحميل البيانات والإعدادات
LoadQuranCSV()
LoadSettings()

; ==============================================================================
; بناء الواجهة الرسومية (GUI)
; ==============================================================================
MyGui := Gui(, "نظام تقطيع الملفات الصوتية")
MyGui.SetFont("s10", "Segoe UI")
MyGui.BackColor := "F0F0F0"

; زر اختيار الملف
MyGui.Add("Button", "x10 y10 w140 h30", "📂 اختيار ملف سورة").OnEvent("Click", SelectAudioFile)
Global LblFile := MyGui.Add("Text", "x+10 yp+5 w680 cBlue", "يرجى اختيار ملف...")

; زر التشغيل
MyGui.Add("Button", "x10 y+10 w140 h30", "▶️ تشغيل").OnEvent("Click", (*) => PlayAudio())

; زر الإيقاف
MyGui.Add("Button", "x+10 yp w140 h30", "⏸️ إيقاف").OnEvent("Click", (*) => PauseAudio())

; زر تسجيل نهاية الآية
Global BtnMark := MyGui.Add("Button", "x+10 yp w140 h30", "✂️ تسجيل نهاية آية")
BtnMark.OnEvent("Click", MarkAyahEnd)

; معلومات الآية
MyGui.SetFont("s11 bold")
Global LblInfo := MyGui.Add("Text", "x10 y+20 w840 Center", "سورة: ... | آية: ...")

; النص القرآني - مع شريط تمرير عمودي
MyGui.SetFont("s16", "Traditional Arabic")
Global EditVerse := MyGui.Add("Edit", "x10 y+10 w840 h500 ReadOnly  Right +VScroll BackgroundSilver", "...")

; شريط الحالة
MyGui.SetFont("s12")  ; حجم الخط 10
Global SB := MyGui.Add("StatusBar")
SB.SetText("  جاهز.")

; مشغل الميديا
Global WMP := MyGui.Add("ActiveX", "w0 h0", "WMPlayer.OCX").Value
WMP.settings.autoStart := false
WMP.settings.volume := 100

; رصد نهاية الملف الصوتي
ComObjConnect(WMP, "WMP_")

MyGui.OnEvent("Close", (*) => ExitApp())

MyGui.Show("w860 h650")

ApplyLastSettings()
UpdateInterface()

; ==============================================================================
; الوظائف الأساسية
; ==============================================================================

SelectAudioFile(*) {
    Selected := FileSelect(1, , "اختر ملف السورة (يحتوي على رقم السورة)", "Audio (*.mp3; *.wav)")
    if !Selected
        return

    SplitPath Selected, &FileName
    
    ; محاولة استخراج رقم السورة من اسم الملف تلقائياً
    if RegExMatch(FileName, "\d+", &Match) {
        DetectedNum := Integer(Match[0])
        if (DetectedNum >= 1 && DetectedNum <= 114) {
             Global CurrentSuraID := DetectedNum
             Global CurrentAyahNum := 1
             Global LastTimestamp := 0
             Global FullAudioPath := Selected
             
             SaveSettings()
             LoadAudioToPlayer(FullAudioPath)
             UpdateInterface()
             SB.SetText("  📂 تم تحميل السورة رقم " DetectedNum " - جاهز للبدء من الآية 1")
        } else {
             MsgBox "الرقم في الملف (" DetectedNum ") غير صحيح."
        }
    } else {
        MsgBox "اسم الملف لا يحتوي على رقم سورة!"
    }
}

PlayAudio() {
    if (FullAudioPath = "") {
        MsgBox "اختر الملف أولاً!"
        return
    }
    WMP.controls.play()
    SB.SetText("  ▶️ جاري التشغيل - اضغط 'تسجيل نهاية آية' عند نهاية كل آية")
}

PauseAudio() {
    WMP.controls.pause()
    SB.SetText("  ⏸️ تم إيقاف التشغيل مؤقتاً")
}

; دالة رصد نهاية الملف الصوتي
WMP_PlayStateChange(NewState, *) {
    ; NewState = 8 يعني انتهى الملف (Media Ended)
    if (NewState = 8) {
        ; تسجيل المقطع الأخير تلقائياً
        if (FullAudioPath != "" && LastTimestamp > 0) {
            EndTimestamp := WMP.currentMedia.duration * 1000
            LogAyah(CurrentSuraID, CurrentAyahNum, LastTimestamp, EndTimestamp)
            SB.SetText("  ✅ تم تسجيل الآية الأخيرة (" CurrentAyahNum ") تلقائياً عند نهاية الملف")
            
            Global CurrentAyahNum += 1
            
            ; الانتقال لمرحلة الإنشاء
            Sleep 500
            Result := MsgBox("انتهى الملف الصوتي.`n`nهل تريد إنشاء ملفات الآيات المنفصلة الآن؟", "اكتمل التسجيل", "YesNo Icon?")
            
            if (Result = "Yes") {
                ProcessAllAyahs()
            } else {
                if FileExist(Ini_File)
                    FileDelete Ini_File
                ExitApp
            }
        }
    }
}

LoadAudioToPlayer(Path) {
    Global FullAudioPath := Path
    LblFile.Value := ExtractFileName(FullAudioPath)
    WMP.URL := FullAudioPath
    WMP.controls.stop()
	 WMP.settings.rate := 0.85 
    IniWrite FullAudioPath, Ini_File, "Media", "LastAudioPath"
    
    if (LastTimestamp > 0) {

        WMP.controls.currentPosition := LastTimestamp / 1000
        SB.SetText("  ✅ تم استعادة الآية " CurrentAyahNum " من سورة " CurrentSuraID " - الموضع: " Round(LastTimestamp/1000) "ث")
    } else {
        SB.SetText("  📖 سورة " CurrentSuraID " جاهزة - ابدأ من الآية الأولى")
    }
}

MarkAyahEnd(*) {
    if (FullAudioPath = "") {
        MsgBox "اختر الملف أولاً!"
        return
    }
    
    ; الحصول على التوقيت الحالي
    CurrentPos := WMP.controls.currentPosition * 1000
    
    ; تجاهل إذا كان قريب جداً من الموضع السابق
    if (CurrentPos <= LastTimestamp + 300)
        return
    
    ; تسجيل في log.txt
    EndTimestamp := CurrentPos
    LogAyah(CurrentSuraID, CurrentAyahNum, LastTimestamp, EndTimestamp)
    
    SB.SetText("  ✅ تم تسجيل الآية " CurrentAyahNum " من سورة " CurrentSuraID)
    
    ; تحديث للآية التالية
    Global LastTimestamp := CurrentPos
    Global CurrentAyahNum += 1
    
    ; التحقق من نهاية السورة
    if !QuranData[CurrentSuraID].Has(CurrentAyahNum) {
        WMP.controls.pause()
        
        Result := MsgBox("انتهت آيات هذه السورة.`n`nهل تريد إنشاء ملفات الآيات المنفصلة الآن؟", "اكتمل التسجيل", "YesNo Icon?")
        
        if (Result = "Yes") {
            ProcessAllAyahs()
        } else {
            ; حذف ملف الإعدادات فقط (نحتفظ بـ log.txt)
            if FileExist(Ini_File)
                FileDelete Ini_File
            ExitApp
        }
        return
    }
    
    ; تحديث رقم الآية فقط بدون إعادة بناء النص
    if QuranData.Has(CurrentSuraID) && QuranData[CurrentSuraID].Has(CurrentAyahNum) {
        LblInfo.Value := "سورة: " CurrentSuraID "  |  آية: " CurrentAyahNum " من " QuranData[CurrentSuraID].Count
		 SendMessage 0x115, 1, 0, EditVerse  ; تمرير سطر واحد للأعلى
		 SendMessage 0x115, 1, 0, EditVerse  ; تمرير سطر واحد للأعلى
	}
    SaveSettings()
}

#HotIf WinActive("Audio Segmenter v4")
Left::  WMP.controls.currentPosition -= 5
Right:: WMP.controls.currentPosition += 5
#HotIf

; ==============================================================================
; الدوال المساعدة
; ==============================================================================

ProcessAllAyahs() {
    SB.SetText("  ⏳ جاري إنشاء ملفات الآيات...")
    
    ; قراءة ملف log.txt
    if !FileExist(Log_File) {
        MsgBox "لا يوجد ملف log.txt!"
        return
    }
    
    LogContent := FileRead(Log_File, "UTF-8")
    TotalAyahs := 0
    
    Loop Parse, LogContent, "`n", "`r"
    {
        if (A_LoopField = "")
            continue
            
        ; تحليل السطر: 001:001 | 0 -> 5234 ms أو 001:001 | 0.5 -> 5234.78 ms
        if RegExMatch(A_LoopField, "(\d+):(\d+) \| ([\d.]+) -> ([\d.]+)", &Match) {
            Sura := Integer(Match[1])
            Ayah := Integer(Match[2])
            StartMs := Round(Float(Match[3]))
            EndMs := Round(Float(Match[4]))
            
            ; إنشاء اسم الملف
            SuraFmt := Format("{:03}", Sura)
            AyahFmt := Format("{:03}", Ayah)
            TargetFile := Output_Dir "\" SuraFmt AyahFmt ".mp3"
            
            ; استدعاء Python لتقطيع الآية
            RunStr := 'python "' Py_Script '" "' FullAudioPath '" ' StartMs ' ' EndMs ' "' TargetFile '"'
            RunWait RunStr,, "Hide"
            
            TotalAyahs++
            SB.SetText("  ⏳ تم إنشاء الآية " AyahFmt " من " SuraFmt " (" TotalAyahs " آية)")
            
            ; فاصل زمني لضمان كتابة الملف
            Sleep 100
        }
    }
    
    SB.SetText("  ✅ اكتمل! تم إنشاء " TotalAyahs " ملف بنجاح")
    MsgBox "تم إنشاء " TotalAyahs " ملف صوتي بنجاح في:`n" Output_Dir, "اكتمل", "Iconi"
    
    ; حذف ملف الإعدادات فقط (نحتفظ بـ log.txt)
    if FileExist(Ini_File)
        FileDelete Ini_File
    
    ExitApp
}

NextAyah() {
    Global CurrentAyahNum += 1
    UpdateInterface()
}

UpdateInterface() {
    try {
        if QuranData.Has(CurrentSuraID) {
            ; بناء نص السورة كاملة
            FullSurahText := ""
            Loop QuranData[CurrentSuraID].Count {
                AyahNumber := A_Index
                if QuranData[CurrentSuraID].Has(AyahNumber) {
                    if (AyahNumber > 1)
                        FullSurahText .= "`n`n"
                    FullSurahText .= " (" AyahNumber ") " QuranData[CurrentSuraID][AyahNumber]
                }
            }
            LblInfo.Value := "سورة: " CurrentSuraID "  |  آية: " CurrentAyahNum " من " QuranData[CurrentSuraID].Count
            EditVerse.Value := FullSurahText
        } else {
            EditVerse.Value := "---"
        }
    }
}

ApplyLastSettings() {
    SavedPath := IniRead(Ini_File, "Media", "LastAudioPath", "")
    if (SavedPath != "" && FileExist(SavedPath)) {
        Global FullAudioPath := SavedPath
        LblFile.Value := ExtractFileName(FullAudioPath)
        WMP.URL := FullAudioPath
        WMP.controls.stop()
        if (LastTimestamp > 0)
            WMP.controls.currentPosition := LastTimestamp / 1000
    }
}

LoadQuranCSV() {
    if !FileExist(CSV_FilePath)
        return
    
    ; قراءة الملف UTF-8 لضمان العربية
    try {
        FileContent := FileRead(CSV_FilePath, "UTF-8")
        Loop Parse, FileContent, "`n", "`r"
        {
            if (A_Index = 1 || A_LoopField = "")
                continue 

            Line := StrReplace(A_LoopField, '"', '')
            Parts := StrSplit(Line, ",")
            if (Parts.Length >= 4) {
                Sura := Integer(Parts[2]), Aya := Integer(Parts[3]), Txt := Parts[4]
                if !QuranData.Has(Sura)
                    QuranData[Sura] := Map()
                QuranData[Sura][Aya] := Txt
            }
        }
    } catch {
        MsgBox "خطأ في قراءة ملف CSV"
    }
}

LoadSettings() {
    try {
        Global CurrentSuraID := Integer(IniRead(Ini_File, "LastPosition", "Sura", 1))
        Global CurrentAyahNum := Integer(IniRead(Ini_File, "LastPosition", "Aya", 1))
        Global LastTimestamp := Float(IniRead(Ini_File, "Media", "LastTimestamp", 0))
    }
}

SaveSettings() {
    IniWrite CurrentSuraID, Ini_File, "LastPosition", "Sura"
    IniWrite CurrentAyahNum, Ini_File, "LastPosition", "Aya"
    IniWrite LastTimestamp, Ini_File, "Media", "LastTimestamp"
}

ExtractFileName(Path) {
    SplitPath Path, &Name
    return Name
}

LogAyah(Sura, Ayah, StartMs, EndMs) {
    ; تحويل الأرقام العشرية إلى صحيحة قبل الكتابة
    StartInt := Round(StartMs)
    EndInt := Round(EndMs)
    FileAppend Format("{:03}:{:03} | {} -> {} ms`n", Sura, Ayah, StartInt, EndInt), Log_File, "UTF-8"
}
