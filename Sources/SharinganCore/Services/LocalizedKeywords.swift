import Foundation

/// Natural-language keywords for the quick-add parser, in the world's 25
/// most-spoken languages. All languages are matched *simultaneously* — a line
/// may mix scripts (`ertaga 明天 tomorrow`) and every set is live at once, so
/// keywords are kept deliberately distinctive to avoid eating plain title words.
///
/// Authoring notes:
/// - Everything is lower-cased at match time; for case-less scripts (CJK,
///   Arabic, Indic, Hangul) that is a no-op, so write words in their natural form.
/// - `TaskInputParser` auto-routes each surface form: a form containing a CJK
///   ideograph or kana is scanned as a substring (those scripts have no spaces);
///   a form containing a space is matched as a multi-token phrase; everything
///   else is matched as a whole token.
/// - `weekdays` is 7 entries in `Calendar` weekday order: [Sunday … Saturday]
///   (weekday numbers 1…7).
/// - Compositional fields (`every`, `within`, `dayUnit`, …) drive
///   `every N days` / `in N hours` style phrases. They are only populated for
///   languages whose word order is `[marker] [number] [unit]`; leaving them
///   empty simply disables those phrases for that language (the keyword tokens
///   above still work).
///
/// Translations were sourced carefully but a native-speaker review pass is
/// worthwhile before relying on the longer tail (Hausa, Punjabi, Telugu, Tamil).
struct LocaleKeywords {
    var today: [String] = []
    var tomorrow: [String] = []
    var dayAfterTomorrow: [String] = []
    var yesterday: [String] = []
    var nextWeek: [String] = []
    /// [Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday].
    var weekdays: [[String]] = []

    var daily: [String] = []
    var weekly: [String] = []
    var monthly: [String] = []
    var weekdaysRecur: [String] = []

    /// "every N …" marker(s) — recurrence.
    var every: [String] = []
    /// "in N …" / "after N …" marker(s) — a due offset from now.
    var within: [String] = []
    var dayUnit: [String] = []
    var weekUnit: [String] = []
    var hourUnit: [String] = []
    var minuteUnit: [String] = []

    /// Natural urgency words → P1. Only high is inferred from words; P2/P3 stay
    /// `p2`/`p3` tokens (no distinctive, collision-safe word exists for them).
    var priorityHigh: [String] = []
}

enum LocalizedKeywords {
    /// The 25 languages, roughly by number of speakers. English + Uzbek lead
    /// because they are the app's primary locales.
    static let all: [LocaleKeywords] = [

        // MARK: English
        LocaleKeywords(
            today: ["today"],
            tomorrow: ["tomorrow"],
            dayAfterTomorrow: ["overmorrow"],
            yesterday: ["yesterday"],
            nextWeek: ["next week"],
            weekdays: [["sunday"], ["monday"], ["tuesday"], ["wednesday"],
                       ["thursday"], ["friday"], ["saturday"]],
            daily: ["daily"],
            weekly: ["weekly"],
            monthly: ["monthly"],
            weekdaysRecur: ["weekdays"],
            every: ["every"],
            within: ["in"],
            dayUnit: ["day", "days"],
            weekUnit: ["week", "weeks"],
            hourUnit: ["hour", "hours", "hr", "hrs"],
            minuteUnit: ["minute", "minutes", "min", "mins"],
            priorityHigh: ["urgent", "important", "asap"]
        ),

        // MARK: Uzbek
        LocaleKeywords(
            today: ["bugun"],
            tomorrow: ["ertaga"],
            dayAfterTomorrow: ["indinga", "indamon"],
            yesterday: ["kecha"],
            nextWeek: ["keyingi hafta", "kelasi hafta"],
            weekdays: [["yakshanba"], ["dushanba"], ["seshanba"], ["chorshanba"],
                       ["payshanba"], ["juma"], ["shanba"]],
            daily: ["har kuni", "kunlik"],
            weekly: ["har hafta", "haftalik"],
            monthly: ["har oy", "oylik"],
            weekdaysRecur: ["ish kunlari"],
            every: ["har"],
            dayUnit: ["kun", "kunda"],
            weekUnit: ["hafta"],
            hourUnit: ["soat"],
            minuteUnit: ["daqiqa", "minut"],
            priorityHigh: ["muhim", "shoshilinch", "zudlik"]
        ),

        // MARK: Spanish
        LocaleKeywords(
            today: ["hoy"],
            tomorrow: ["mañana", "manana"],
            dayAfterTomorrow: ["pasado mañana", "pasado manana"],
            yesterday: ["ayer"],
            nextWeek: ["próxima semana", "proxima semana", "semana que viene"],
            weekdays: [["domingo"], ["lunes"], ["martes"], ["miércoles", "miercoles"],
                       ["jueves"], ["viernes"], ["sábado", "sabado"]],
            daily: ["diariamente", "diario", "cada día", "cada dia"],
            weekly: ["semanalmente", "semanal"],
            monthly: ["mensualmente", "mensual"],
            weekdaysRecur: ["entre semana", "días laborables", "dias laborables"],
            every: ["cada"],
            within: ["en"],
            dayUnit: ["día", "dia", "días", "dias"],
            weekUnit: ["semana", "semanas"],
            hourUnit: ["hora", "horas"],
            minuteUnit: ["minuto", "minutos"],
            priorityHigh: ["urgente", "importante"]
        ),

        // MARK: French
        LocaleKeywords(
            today: ["aujourd'hui"],
            tomorrow: ["demain"],
            dayAfterTomorrow: ["après-demain", "apres-demain"],
            yesterday: ["hier"],
            nextWeek: ["semaine prochaine", "la semaine prochaine"],
            weekdays: [["dimanche"], ["lundi"], ["mardi"], ["mercredi"],
                       ["jeudi"], ["vendredi"], ["samedi"]],
            daily: ["quotidien", "quotidiennement", "chaque jour"],
            weekly: ["hebdomadaire", "hebdo"],
            monthly: ["mensuel", "mensuellement"],
            weekdaysRecur: ["en semaine", "jours de semaine"],
            every: ["chaque"],
            within: ["dans"],
            dayUnit: ["jour", "jours"],
            weekUnit: ["semaine", "semaines"],
            hourUnit: ["heure", "heures"],
            minuteUnit: ["minute", "minutes"],
            priorityHigh: ["urgent", "urgente", "important", "importante"]
        ),

        // MARK: Arabic
        LocaleKeywords(
            today: ["اليوم"],
            tomorrow: ["غدا", "غدًا", "بكرة"],
            dayAfterTomorrow: ["بعد غد", "بعد غدٍ"],
            yesterday: ["أمس", "امبارح"],
            nextWeek: ["الأسبوع القادم", "الأسبوع المقبل"],
            weekdays: [["الأحد"], ["الاثنين", "الإثنين"], ["الثلاثاء"], ["الأربعاء"],
                       ["الخميس"], ["الجمعة"], ["السبت"]],
            daily: ["يوميا", "يومي", "يوميًا"],
            weekly: ["أسبوعيا", "اسبوعي", "أسبوعي"],
            monthly: ["شهريا", "شهري", "شهريًا"],
            weekdaysRecur: ["أيام العمل", "أيام الأسبوع"],
            priorityHigh: ["عاجل", "مهم", "هام"]
        ),

        // MARK: Hindi
        LocaleKeywords(
            today: ["आज"],
            tomorrow: ["कल", "आने वाला कल"],
            dayAfterTomorrow: ["परसों"],
            yesterday: ["बीता कल", "गुज़रा कल"],
            nextWeek: ["अगले हफ्ते", "अगले सप्ताह"],
            weekdays: [["रविवार"], ["सोमवार"], ["मंगलवार"], ["बुधवार"],
                       ["गुरुवार"], ["शुक्रवार"], ["शनिवार"]],
            daily: ["रोज़", "रोज", "प्रतिदिन", "हर दिन"],
            weekly: ["साप्ताहिक", "हर हफ्ते", "हर सप्ताह"],
            monthly: ["मासिक", "हर महीने"],
            priorityHigh: ["ज़रूरी", "जरूरी", "महत्वपूर्ण"]
        ),

        // MARK: Bengali
        LocaleKeywords(
            today: ["আজ"],
            tomorrow: ["আগামীকাল", "কাল"],
            dayAfterTomorrow: ["পরশু"],
            yesterday: ["গতকাল"],
            nextWeek: ["আগামী সপ্তাহ"],
            weekdays: [["রবিবার"], ["সোমবার"], ["মঙ্গলবার"], ["বুধবার"],
                       ["বৃহস্পতিবার"], ["শুক্রবার"], ["শনিবার"]],
            daily: ["প্রতিদিন", "রোজ"],
            weekly: ["সাপ্তাহিক"],
            monthly: ["মাসিক"],
            priorityHigh: ["জরুরি", "গুরুত্বপূর্ণ"]
        ),

        // MARK: Portuguese
        LocaleKeywords(
            today: ["hoje"],
            tomorrow: ["amanhã", "amanha"],
            dayAfterTomorrow: ["depois de amanhã", "depois de amanha"],
            yesterday: ["ontem"],
            nextWeek: ["próxima semana", "semana que vem"],
            weekdays: [["domingo"], ["segunda-feira", "segunda"], ["terça-feira", "terça", "terca"],
                       ["quarta-feira", "quarta"], ["quinta-feira", "quinta"],
                       ["sexta-feira", "sexta"], ["sábado", "sabado"]],
            daily: ["diariamente", "diário", "todo dia"],
            weekly: ["semanalmente", "semanal"],
            monthly: ["mensalmente", "mensal"],
            weekdaysRecur: ["dias úteis", "dias uteis"],
            every: ["cada"],
            within: ["em"],
            dayUnit: ["dia", "dias"],
            weekUnit: ["semana", "semanas"],
            hourUnit: ["hora", "horas"],
            minuteUnit: ["minuto", "minutos"],
            priorityHigh: ["urgente", "importante"]
        ),

        // MARK: Russian
        LocaleKeywords(
            today: ["сегодня"],
            tomorrow: ["завтра"],
            dayAfterTomorrow: ["послезавтра"],
            yesterday: ["вчера"],
            nextWeek: ["следующей неделе", "на следующей неделе"],
            weekdays: [["воскресенье"], ["понедельник"], ["вторник"], ["среда"],
                       ["четверг"], ["пятница"], ["суббота"]],
            daily: ["ежедневно", "каждый день"],
            weekly: ["еженедельно", "каждую неделю"],
            monthly: ["ежемесячно", "каждый месяц"],
            weekdaysRecur: ["будни", "по будням"],
            every: ["каждые", "каждый", "каждую"],
            within: ["через"],
            dayUnit: ["день", "дня", "дней"],
            weekUnit: ["неделя", "недели", "недель"],
            hourUnit: ["час", "часа", "часов"],
            minuteUnit: ["минута", "минуты", "минут"],
            priorityHigh: ["срочно", "срочный", "важно", "важный"]
        ),

        // MARK: Urdu
        LocaleKeywords(
            today: ["آج"],
            tomorrow: ["کل", "آنے والا کل"],
            dayAfterTomorrow: ["پرسوں"],
            yesterday: ["گزرا کل", "گزشتہ کل"],
            nextWeek: ["اگلے ہفتے"],
            weekdays: [["اتوار"], ["پیر", "سوموار"], ["منگل"], ["بدھ"],
                       ["جمعرات"], ["جمعہ"], ["ہفتہ"]],
            daily: ["روزانہ", "روز"],
            weekly: ["ہفتہ وار", "ہفتہ‌وار"],
            monthly: ["ماہانہ"],
            priorityHigh: ["فوری", "ضروری", "اہم"]
        ),

        // MARK: Indonesian
        LocaleKeywords(
            today: ["hari ini"],
            tomorrow: ["besok", "esok"],
            dayAfterTomorrow: ["lusa"],
            yesterday: ["kemarin"],
            nextWeek: ["minggu depan", "pekan depan"],
            weekdays: [["minggu"], ["senin"], ["selasa"], ["rabu"],
                       ["kamis"], ["jumat"], ["sabtu"]],
            daily: ["setiap hari", "harian"],
            weekly: ["mingguan", "setiap minggu"],
            monthly: ["bulanan", "setiap bulan"],
            weekdaysRecur: ["hari kerja"],
            every: ["setiap", "tiap"],
            within: ["dalam"],
            dayUnit: ["hari"],
            weekUnit: ["minggu", "pekan"],
            hourUnit: ["jam"],
            minuteUnit: ["menit"],
            priorityHigh: ["penting", "mendesak"]
        ),

        // MARK: German
        LocaleKeywords(
            today: ["heute"],
            tomorrow: ["morgen"],
            dayAfterTomorrow: ["übermorgen", "uebermorgen"],
            yesterday: ["gestern"],
            nextWeek: ["nächste woche", "naechste woche"],
            weekdays: [["sonntag"], ["montag"], ["dienstag"], ["mittwoch"],
                       ["donnerstag"], ["freitag"], ["samstag", "sonnabend"]],
            daily: ["täglich", "taeglich", "jeden tag"],
            weekly: ["wöchentlich", "woechentlich"],
            monthly: ["monatlich"],
            weekdaysRecur: ["wochentags", "werktags"],
            every: ["jeden", "jede", "alle"],
            within: ["in"],
            dayUnit: ["tag", "tage", "tagen"],
            weekUnit: ["woche", "wochen"],
            hourUnit: ["stunde", "stunden"],
            minuteUnit: ["minute", "minuten"],
            priorityHigh: ["dringend", "wichtig"]
        ),

        // MARK: Japanese (CJK — scanned as substrings)
        LocaleKeywords(
            today: ["今日", "きょう"],
            tomorrow: ["明日", "あした", "あす"],
            dayAfterTomorrow: ["明後日", "あさって"],
            yesterday: ["昨日", "きのう"],
            nextWeek: ["来週"],
            weekdays: [["日曜日", "日曜"], ["月曜日", "月曜"], ["火曜日", "火曜"],
                       ["水曜日", "水曜"], ["木曜日", "木曜"], ["金曜日", "金曜"],
                       ["土曜日", "土曜"]],
            daily: ["毎日"],
            weekly: ["毎週"],
            monthly: ["毎月"],
            weekdaysRecur: ["平日"],
            priorityHigh: ["至急", "緊急", "重要"]
        ),

        // MARK: Mandarin Chinese (CJK — scanned as substrings)
        LocaleKeywords(
            today: ["今天", "今日"],
            tomorrow: ["明天", "明日"],
            dayAfterTomorrow: ["后天", "後天"],
            yesterday: ["昨天"],
            nextWeek: ["下周", "下週"],
            weekdays: [["星期日", "星期天", "周日", "週日"], ["星期一", "周一", "週一"],
                       ["星期二", "周二", "週二"], ["星期三", "周三", "週三"],
                       ["星期四", "周四", "週四"], ["星期五", "周五", "週五"],
                       ["星期六", "周六", "週六"]],
            daily: ["每天", "每日"],
            weekly: ["每周", "每週"],
            monthly: ["每月"],
            weekdaysRecur: ["工作日"],
            priorityHigh: ["紧急", "緊急", "重要"]
        ),

        // MARK: Marathi
        LocaleKeywords(
            today: ["आज"],
            tomorrow: ["उद्या"],
            dayAfterTomorrow: ["परवा"],
            yesterday: ["काल"],
            nextWeek: ["पुढच्या आठवड्यात"],
            weekdays: [["रविवार"], ["सोमवार"], ["मंगळवार"], ["बुधवार"],
                       ["गुरुवार"], ["शुक्रवार"], ["शनिवार"]],
            daily: ["दररोज", "रोज"],
            weekly: ["साप्ताहिक"],
            monthly: ["मासिक"],
            priorityHigh: ["तातडीचे", "महत्त्वाचे"]
        ),

        // MARK: Telugu
        LocaleKeywords(
            today: ["ఈరోజు", "నేడు"],
            tomorrow: ["రేపు"],
            dayAfterTomorrow: ["ఎల్లుండి"],
            yesterday: ["నిన్న"],
            nextWeek: ["వచ్చే వారం"],
            weekdays: [["ఆదివారం"], ["సోమవారం"], ["మంగళవారం"], ["బుధవారం"],
                       ["గురువారం"], ["శుక్రవారం"], ["శనివారం"]],
            daily: ["ప్రతిరోజు", "రోజూ"],
            weekly: ["వారానికి", "వారంవారం"],
            monthly: ["నెలవారీ"],
            priorityHigh: ["అత్యవసరం", "ముఖ్యమైన"]
        ),

        // MARK: Turkish
        LocaleKeywords(
            today: ["bugün", "bugun"],
            tomorrow: ["yarın", "yarin"],
            dayAfterTomorrow: ["öbür gün", "obur gun"],
            yesterday: ["dün", "dun"],
            nextWeek: ["gelecek hafta", "haftaya"],
            weekdays: [["pazar"], ["pazartesi"], ["salı", "sali"], ["çarşamba", "carsamba"],
                       ["perşembe", "persembe"], ["cuma"], ["cumartesi"]],
            daily: ["günlük", "gunluk", "her gün", "her gun"],
            weekly: ["haftalık", "haftalik", "her hafta"],
            monthly: ["aylık", "aylik", "her ay"],
            weekdaysRecur: ["hafta içi", "hafta ici"],
            every: ["her"],
            dayUnit: ["gün", "gun", "günde", "gunde"],
            weekUnit: ["hafta"],
            hourUnit: ["saat"],
            minuteUnit: ["dakika"],
            priorityHigh: ["acil", "önemli", "onemli"]
        ),

        // MARK: Tamil
        LocaleKeywords(
            today: ["இன்று", "இன்னைக்கு"],
            tomorrow: ["நாளை"],
            dayAfterTomorrow: ["நாளன்று", "மறுநாள்"],
            yesterday: ["நேற்று"],
            nextWeek: ["அடுத்த வாரம்"],
            weekdays: [["ஞாயிறு"], ["திங்கள்"], ["செவ்வாய்"], ["புதன்"],
                       ["வியாழன்"], ["வெள்ளி"], ["சனி"]],
            daily: ["தினமும்", "தினசரி"],
            weekly: ["வாராந்திர", "வாரந்தோறும்"],
            monthly: ["மாதாந்திர", "மாதந்தோறும்"],
            priorityHigh: ["அவசரம்", "முக்கியம்"]
        ),

        // MARK: Vietnamese
        LocaleKeywords(
            today: ["hôm nay"],
            tomorrow: ["ngày mai"],
            dayAfterTomorrow: ["ngày kia", "ngày mốt"],
            yesterday: ["hôm qua"],
            nextWeek: ["tuần sau", "tuần tới"],
            weekdays: [["chủ nhật"], ["thứ hai"], ["thứ ba"], ["thứ tư"],
                       ["thứ năm"], ["thứ sáu"], ["thứ bảy"]],
            daily: ["hằng ngày", "hàng ngày", "mỗi ngày"],
            weekly: ["hằng tuần", "hàng tuần"],
            monthly: ["hằng tháng", "hàng tháng"],
            weekdaysRecur: ["ngày thường"],
            every: ["mỗi"],
            within: ["trong", "sau"],
            dayUnit: ["ngày"],
            weekUnit: ["tuần"],
            hourUnit: ["giờ", "tiếng"],
            minuteUnit: ["phút"],
            priorityHigh: ["khẩn cấp", "quan trọng", "gấp"]
        ),

        // MARK: Korean
        LocaleKeywords(
            today: ["오늘"],
            tomorrow: ["내일"],
            dayAfterTomorrow: ["모레"],
            yesterday: ["어제"],
            nextWeek: ["다음 주", "다음주"],
            weekdays: [["일요일"], ["월요일"], ["화요일"], ["수요일"],
                       ["목요일"], ["금요일"], ["토요일"]],
            daily: ["매일"],
            weekly: ["매주"],
            monthly: ["매달", "매월"],
            weekdaysRecur: ["평일"],
            priorityHigh: ["긴급", "중요", "급함"]
        ),

        // MARK: Persian
        LocaleKeywords(
            today: ["امروز"],
            tomorrow: ["فردا"],
            dayAfterTomorrow: ["پس فردا", "پس‌فردا"],
            yesterday: ["دیروز"],
            nextWeek: ["هفته بعد", "هفته آینده"],
            weekdays: [["یکشنبه"], ["دوشنبه"], ["سه‌شنبه", "سه شنبه"], ["چهارشنبه"],
                       ["پنجشنبه", "پنج‌شنبه"], ["جمعه"], ["شنبه"]],
            daily: ["روزانه", "هر روز"],
            weekly: ["هفتگی", "هر هفته"],
            monthly: ["ماهانه", "هر ماه"],
            priorityHigh: ["فوری", "مهم"]
        ),

        // MARK: Italian
        LocaleKeywords(
            today: ["oggi"],
            tomorrow: ["domani"],
            dayAfterTomorrow: ["dopodomani"],
            yesterday: ["ieri"],
            nextWeek: ["prossima settimana", "settimana prossima"],
            weekdays: [["domenica"], ["lunedì", "lunedi"], ["martedì", "martedi"],
                       ["mercoledì", "mercoledi"], ["giovedì", "giovedi"],
                       ["venerdì", "venerdi"], ["sabato"]],
            daily: ["giornaliero", "quotidiano", "ogni giorno"],
            weekly: ["settimanale", "ogni settimana"],
            monthly: ["mensile", "ogni mese"],
            weekdaysRecur: ["giorni feriali"],
            every: ["ogni"],
            within: ["tra", "fra"],
            dayUnit: ["giorno", "giorni"],
            weekUnit: ["settimana", "settimane"],
            hourUnit: ["ora", "ore"],
            minuteUnit: ["minuto", "minuti"],
            priorityHigh: ["urgente", "importante"]
        ),

        // MARK: Hausa
        LocaleKeywords(
            today: ["yau"],
            tomorrow: ["gobe"],
            dayAfterTomorrow: ["jibi"],
            yesterday: ["jiya"],
            nextWeek: ["mako mai zuwa"],
            weekdays: [["lahadi"], ["litinin"], ["talata"], ["laraba"],
                       ["alhamis"], ["jumma'a"], ["asabar"]],
            daily: ["kullum", "kowace rana"],
            weekly: ["kowane mako"],
            monthly: ["kowane wata"],
            priorityHigh: ["gaggawa", "muhimmi"]
        ),

        // MARK: Swahili
        LocaleKeywords(
            today: ["leo"],
            tomorrow: ["kesho"],
            dayAfterTomorrow: ["kesho kutwa"],
            yesterday: ["jana"],
            nextWeek: ["wiki ijayo"],
            weekdays: [["jumapili"], ["jumatatu"], ["jumanne"], ["jumatano"],
                       ["alhamisi"], ["ijumaa"], ["jumamosi"]],
            daily: ["kila siku"],
            weekly: ["kila wiki"],
            monthly: ["kila mwezi"],
            priorityHigh: ["haraka", "muhimu"]
        ),

        // MARK: Punjabi
        LocaleKeywords(
            today: ["ਅੱਜ"],
            tomorrow: ["ਭਲਕੇ", "ਕੱਲ੍ਹ"],
            dayAfterTomorrow: ["ਪਰਸੋਂ"],
            yesterday: ["ਬੀਤਿਆ ਕੱਲ੍ਹ"],
            nextWeek: ["ਅਗਲੇ ਹਫ਼ਤੇ"],
            weekdays: [["ਐਤਵਾਰ"], ["ਸੋਮਵਾਰ"], ["ਮੰਗਲਵਾਰ"], ["ਬੁੱਧਵਾਰ"],
                       ["ਵੀਰਵਾਰ"], ["ਸ਼ੁੱਕਰਵਾਰ"], ["ਸ਼ਨਿੱਚਰਵਾਰ"]],
            daily: ["ਰੋਜ਼ਾਨਾ", "ਹਰ ਰੋਜ਼"],
            weekly: ["ਹਫ਼ਤਾਵਾਰ"],
            monthly: ["ਮਹੀਨਾਵਾਰ"],
            priorityHigh: ["ਜ਼ਰੂਰੀ", "ਅਹਿਮ"]
        ),
    ]
}
