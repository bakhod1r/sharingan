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
///   (weekday numbers 1…7). `months` is 12 entries, January … December.
/// - Parts of day map to a default clock time (morning 09:00, noon 12:00,
///   afternoon 15:00, evening 18:00, tonight/night 20:00, midnight 00:00) and
///   combine with a day word — "tomorrow evening" = tomorrow 18:00.
/// - Compositional fields drive `every N days` / `in N hours` phrases:
///   `every`/`within` are prepositional markers (`every 3 days`, `in 2 hours`),
///   `after` is the postpositional marker some languages use (`2 soatdan keyin`,
///   `2 saat sonra`). They only fire with a number + a known unit, so bare
///   markers stay in the title. Coverage of these varies by language (full for
///   the prepositional Latin/Cyrillic set, plus Uzbek/Turkish/Hindi
///   postpositional); month-name dates are populated for Latin/Cyrillic scripts,
///   and every language still accepts numeric `12.08` dates.
///
/// Translations were sourced carefully but a native-speaker review pass is
/// worthwhile before relying on the longer tail (Hausa, Punjabi, Telugu, Tamil).
struct LocaleKeywords {
    var today: [String] = []
    var tomorrow: [String] = []
    var dayAfterTomorrow: [String] = []
    var yesterday: [String] = []
    var nextWeek: [String] = []
    var nextMonth: [String] = []
    var nextYear: [String] = []
    var thisWeek: [String] = []
    var weekend: [String] = []
    /// [Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday].
    var weekdays: [[String]] = []
    /// [January … December] — single-token, non-CJK names only are indexed.
    var months: [[String]] = []

    // Parts of day → a default clock time.
    var morning: [String] = []
    var noon: [String] = []
    var afternoon: [String] = []
    var evening: [String] = []
    var nightTime: [String] = []
    var midnight: [String] = []

    var daily: [String] = []
    var weekly: [String] = []
    var monthly: [String] = []
    var weekdaysRecur: [String] = []

    /// "every N …" marker(s) — recurrence.
    var every: [String] = []
    /// Prepositional "in N …" marker(s) — a due offset from now.
    var within: [String] = []
    /// Postpositional "N … <after>" marker(s) — a due offset from now.
    var after: [String] = []
    var dayUnit: [String] = []
    var weekUnit: [String] = []
    var monthUnit: [String] = []
    var yearUnit: [String] = []
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
            nextMonth: ["next month"],
            nextYear: ["next year"],
            thisWeek: ["this week"],
            weekend: ["weekend", "this weekend"],
            weekdays: [["sunday"], ["monday"], ["tuesday"], ["wednesday"],
                       ["thursday"], ["friday"], ["saturday"]],
            months: [["january", "jan"], ["february", "feb"], ["march", "mar"],
                     ["april", "apr"], ["may"], ["june", "jun"], ["july", "jul"],
                     ["august", "aug"], ["september", "sep", "sept"],
                     ["october", "oct"], ["november", "nov"], ["december", "dec"]],
            morning: ["morning", "this morning"],
            noon: ["noon", "midday"],
            afternoon: ["afternoon"],
            evening: ["evening"],
            nightTime: ["tonight"],
            midnight: ["midnight"],
            daily: ["daily"],
            weekly: ["weekly"],
            monthly: ["monthly"],
            weekdaysRecur: ["weekdays"],
            every: ["every"],
            within: ["in"],
            dayUnit: ["day", "days"],
            weekUnit: ["week", "weeks"],
            monthUnit: ["month", "months"],
            yearUnit: ["year", "years"],
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
            nextMonth: ["keyingi oy", "kelasi oy"],
            nextYear: ["keyingi yil", "kelasi yil"],
            thisWeek: ["shu hafta", "bu hafta"],
            weekend: ["hafta oxiri", "dam olish kunlari"],
            weekdays: [["yakshanba"], ["dushanba"], ["seshanba"], ["chorshanba"],
                       ["payshanba"], ["juma"], ["shanba"]],
            months: [["yanvar"], ["fevral"], ["mart"], ["aprel"], ["may"], ["iyun"],
                     ["iyul"], ["avgust"], ["sentabr"], ["oktabr"], ["noyabr"], ["dekabr"]],
            morning: ["ertalab"],
            noon: ["peshin", "tushlik"],
            afternoon: ["tushdan keyin"],
            evening: ["kechqurun"],
            nightTime: ["kechasi", "bugun kechqurun"],
            midnight: ["yarim tun"],
            daily: ["har kuni", "kunlik"],
            weekly: ["har hafta", "haftalik"],
            monthly: ["har oy", "oylik"],
            weekdaysRecur: ["ish kunlari"],
            every: ["har"],
            after: ["keyin"],
            dayUnit: ["kun", "kunda", "kundan"],
            weekUnit: ["hafta", "haftadan"],
            monthUnit: ["oy", "oydan"],
            yearUnit: ["yil", "yildan"],
            hourUnit: ["soat", "soatdan"],
            minuteUnit: ["daqiqa", "daqiqadan", "minut"],
            priorityHigh: ["muhim", "shoshilinch", "zudlik"]
        ),

        // MARK: Spanish
        LocaleKeywords(
            today: ["hoy"],
            tomorrow: ["mañana", "manana"],
            dayAfterTomorrow: ["pasado mañana", "pasado manana"],
            yesterday: ["ayer"],
            nextWeek: ["próxima semana", "proxima semana", "semana que viene"],
            nextMonth: ["próximo mes", "proximo mes", "mes que viene"],
            nextYear: ["próximo año", "proximo ano", "año que viene"],
            thisWeek: ["esta semana"],
            weekend: ["fin de semana"],
            weekdays: [["domingo"], ["lunes"], ["martes"], ["miércoles", "miercoles"],
                       ["jueves"], ["viernes"], ["sábado", "sabado"]],
            months: [["enero"], ["febrero"], ["marzo"], ["abril"], ["mayo"], ["junio"],
                     ["julio"], ["agosto"], ["septiembre"], ["octubre"], ["noviembre"], ["diciembre"]],
            noon: ["mediodía", "mediodia"],
            afternoon: ["tarde"],
            evening: ["noche", "esta noche"],
            midnight: ["medianoche"],
            daily: ["diariamente", "diario", "cada día", "cada dia"],
            weekly: ["semanalmente", "semanal"],
            monthly: ["mensualmente", "mensual"],
            weekdaysRecur: ["entre semana", "días laborables", "dias laborables"],
            every: ["cada"],
            within: ["en"],
            dayUnit: ["día", "dia", "días", "dias"],
            weekUnit: ["semana", "semanas"],
            monthUnit: ["mes", "meses"],
            yearUnit: ["año", "ano", "años", "anos"],
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
            nextMonth: ["mois prochain", "le mois prochain"],
            nextYear: ["année prochaine", "annee prochaine"],
            thisWeek: ["cette semaine"],
            weekend: ["week-end", "ce week-end"],
            weekdays: [["dimanche"], ["lundi"], ["mardi"], ["mercredi"],
                       ["jeudi"], ["vendredi"], ["samedi"]],
            months: [["janvier"], ["février", "fevrier"], ["mars"], ["avril"], ["mai"],
                     ["juin"], ["juillet"], ["août", "aout"], ["septembre"],
                     ["octobre"], ["novembre"], ["décembre", "decembre"]],
            morning: ["matin", "ce matin"],
            noon: ["midi"],
            afternoon: ["après-midi", "apres-midi"],
            evening: ["soir", "ce soir"],
            midnight: ["minuit"],
            daily: ["quotidien", "quotidiennement", "chaque jour"],
            weekly: ["hebdomadaire", "hebdo"],
            monthly: ["mensuel", "mensuellement"],
            weekdaysRecur: ["en semaine", "jours de semaine"],
            every: ["chaque"],
            within: ["dans"],
            dayUnit: ["jour", "jours"],
            weekUnit: ["semaine", "semaines"],
            monthUnit: ["mois"],
            yearUnit: ["an", "ans", "année", "annee", "années", "annees"],
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
            nextMonth: ["الشهر القادم", "الشهر المقبل"],
            nextYear: ["السنة القادمة", "العام المقبل"],
            thisWeek: ["هذا الأسبوع"],
            weekend: ["عطلة نهاية الأسبوع", "نهاية الأسبوع"],
            weekdays: [["الأحد"], ["الاثنين", "الإثنين"], ["الثلاثاء"], ["الأربعاء"],
                       ["الخميس"], ["الجمعة"], ["السبت"]],
            morning: ["صباحا", "الصباح"],
            noon: ["ظهرا", "الظهر"],
            afternoon: ["بعد الظهر"],
            evening: ["مساء", "المساء"],
            nightTime: ["الليلة", "مساء اليوم"],
            midnight: ["منتصف الليل"],
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
            nextMonth: ["अगले महीने"],
            nextYear: ["अगले साल"],
            thisWeek: ["इस हफ्ते"],
            weekend: ["सप्ताहांत"],
            weekdays: [["रविवार"], ["सोमवार"], ["मंगलवार"], ["बुधवार"],
                       ["गुरुवार"], ["शुक्रवार"], ["शनिवार"]],
            morning: ["सुबह"],
            noon: ["दोपहर"],
            afternoon: ["दोपहर बाद"],
            evening: ["शाम"],
            nightTime: ["आज रात", "रात"],
            midnight: ["आधी रात"],
            daily: ["रोज़", "रोज", "प्रतिदिन", "हर दिन"],
            weekly: ["साप्ताहिक", "हर हफ्ते", "हर सप्ताह"],
            monthly: ["मासिक", "हर महीने"],
            after: ["में"],
            dayUnit: ["दिन"],
            weekUnit: ["हफ्ते", "सप्ताह"],
            monthUnit: ["महीने", "महीना"],
            yearUnit: ["साल", "वर्ष"],
            hourUnit: ["घंटे", "घंटा"],
            minuteUnit: ["मिनट"],
            priorityHigh: ["ज़रूरी", "जरूरी", "महत्वपूर्ण"]
        ),

        // MARK: Bengali
        LocaleKeywords(
            today: ["আজ"],
            tomorrow: ["আগামীকাল", "কাল"],
            dayAfterTomorrow: ["পরশু"],
            yesterday: ["গতকাল"],
            nextWeek: ["আগামী সপ্তাহ"],
            nextMonth: ["আগামী মাস"],
            nextYear: ["আগামী বছর"],
            thisWeek: ["এই সপ্তাহ"],
            weekend: ["সপ্তাহান্ত"],
            weekdays: [["রবিবার"], ["সোমবার"], ["মঙ্গলবার"], ["বুধবার"],
                       ["বৃহস্পতিবার"], ["শুক্রবার"], ["শনিবার"]],
            morning: ["সকাল"],
            noon: ["দুপুর"],
            afternoon: ["বিকাল"],
            evening: ["সন্ধ্যা"],
            nightTime: ["আজ রাতে", "রাত"],
            midnight: ["মধ্যরাত"],
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
            nextMonth: ["próximo mês", "proximo mes", "mês que vem"],
            nextYear: ["próximo ano", "proximo ano", "ano que vem"],
            thisWeek: ["esta semana"],
            weekend: ["fim de semana"],
            weekdays: [["domingo"], ["segunda-feira", "segunda"], ["terça-feira", "terça", "terca"],
                       ["quarta-feira", "quarta"], ["quinta-feira", "quinta"],
                       ["sexta-feira", "sexta"], ["sábado", "sabado"]],
            months: [["janeiro"], ["fevereiro"], ["março", "marco"], ["abril"], ["maio"],
                     ["junho"], ["julho"], ["agosto"], ["setembro"], ["outubro"],
                     ["novembro"], ["dezembro"]],
            morning: ["manhã", "manha"],
            noon: ["meio-dia"],
            afternoon: ["tarde"],
            evening: ["noite"],
            nightTime: ["hoje à noite", "hoje a noite"],
            midnight: ["meia-noite"],
            daily: ["diariamente", "diário", "todo dia"],
            weekly: ["semanalmente", "semanal"],
            monthly: ["mensalmente", "mensal"],
            weekdaysRecur: ["dias úteis", "dias uteis"],
            every: ["cada"],
            within: ["em"],
            dayUnit: ["dia", "dias"],
            weekUnit: ["semana", "semanas"],
            monthUnit: ["mês", "mes", "meses"],
            yearUnit: ["ano", "anos"],
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
            nextMonth: ["следующем месяце", "следующий месяц"],
            nextYear: ["следующем году", "следующий год"],
            thisWeek: ["на этой неделе", "этой неделе"],
            weekend: ["выходные", "в выходные"],
            weekdays: [["воскресенье"], ["понедельник"], ["вторник"], ["среда"],
                       ["четверг"], ["пятница"], ["суббота"]],
            months: [["января"], ["февраля"], ["марта"], ["апреля"], ["мая"], ["июня"],
                     ["июля"], ["августа"], ["сентября"], ["октября"], ["ноября"], ["декабря"]],
            morning: ["утром", "утро"],
            noon: ["полдень"],
            afternoon: ["днём", "днем"],
            evening: ["вечером", "вечер"],
            nightTime: ["сегодня вечером", "ночью"],
            midnight: ["полночь"],
            daily: ["ежедневно", "каждый день"],
            weekly: ["еженедельно", "каждую неделю"],
            monthly: ["ежемесячно", "каждый месяц"],
            weekdaysRecur: ["будни", "по будням"],
            every: ["каждые", "каждый", "каждую"],
            within: ["через"],
            dayUnit: ["день", "дня", "дней"],
            weekUnit: ["неделя", "недели", "недель"],
            monthUnit: ["месяц", "месяца", "месяцев"],
            yearUnit: ["год", "года", "лет"],
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
            nextMonth: ["اگلے مہینے"],
            nextYear: ["اگلے سال"],
            thisWeek: ["اس ہفتے"],
            weekend: ["ہفتے کے آخر میں"],
            weekdays: [["اتوار"], ["پیر", "سوموار"], ["منگل"], ["بدھ"],
                       ["جمعرات"], ["جمعہ"], ["ہفتہ"]],
            morning: ["صبح"],
            noon: ["دوپہر"],
            afternoon: ["سہ پہر"],
            evening: ["شام"],
            nightTime: ["آج رات", "رات"],
            midnight: ["آدھی رات"],
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
            nextMonth: ["bulan depan"],
            nextYear: ["tahun depan"],
            thisWeek: ["minggu ini"],
            weekend: ["akhir pekan"],
            weekdays: [["minggu"], ["senin"], ["selasa"], ["rabu"],
                       ["kamis"], ["jumat"], ["sabtu"]],
            months: [["januari"], ["februari"], ["maret"], ["april"], ["mei"], ["juni"],
                     ["juli"], ["agustus"], ["september"], ["oktober"], ["november"], ["desember"]],
            morning: ["pagi"],
            noon: ["siang", "tengah hari"],
            afternoon: ["sore"],
            evening: ["malam"],
            nightTime: ["malam ini", "nanti malam"],
            midnight: ["tengah malam"],
            daily: ["setiap hari", "harian"],
            weekly: ["mingguan", "setiap minggu"],
            monthly: ["bulanan", "setiap bulan"],
            weekdaysRecur: ["hari kerja"],
            every: ["setiap", "tiap"],
            within: ["dalam"],
            dayUnit: ["hari"],
            weekUnit: ["minggu", "pekan"],
            monthUnit: ["bulan"],
            yearUnit: ["tahun"],
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
            nextMonth: ["nächsten monat", "naechsten monat"],
            nextYear: ["nächstes jahr", "naechstes jahr"],
            thisWeek: ["diese woche"],
            weekend: ["wochenende"],
            weekdays: [["sonntag"], ["montag"], ["dienstag"], ["mittwoch"],
                       ["donnerstag"], ["freitag"], ["samstag", "sonnabend"]],
            months: [["januar"], ["februar"], ["märz", "maerz"], ["april"], ["mai"], ["juni"],
                     ["juli"], ["august"], ["september"], ["oktober"], ["november"], ["dezember"]],
            morning: ["morgens", "früh", "frueh"],
            noon: ["mittag"],
            afternoon: ["nachmittag"],
            evening: ["abend"],
            nightTime: ["heute abend", "heute nacht"],
            midnight: ["mitternacht"],
            daily: ["täglich", "taeglich", "jeden tag"],
            weekly: ["wöchentlich", "woechentlich"],
            monthly: ["monatlich"],
            weekdaysRecur: ["wochentags", "werktags"],
            every: ["jeden", "jede", "alle"],
            within: ["in"],
            dayUnit: ["tag", "tage", "tagen"],
            weekUnit: ["woche", "wochen"],
            monthUnit: ["monat", "monate", "monaten"],
            yearUnit: ["jahr", "jahre", "jahren"],
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
            nextMonth: ["来月"],
            nextYear: ["来年"],
            thisWeek: ["今週"],
            weekend: ["週末"],
            weekdays: [["日曜日", "日曜"], ["月曜日", "月曜"], ["火曜日", "火曜"],
                       ["水曜日", "水曜"], ["木曜日", "木曜"], ["金曜日", "金曜"],
                       ["土曜日", "土曜"]],
            morning: ["朝", "午前"],
            noon: ["正午"],
            afternoon: ["午後"],
            evening: ["夕方"],
            nightTime: ["今夜", "今晩"],
            midnight: ["深夜", "真夜中"],
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
            nextMonth: ["下个月", "下個月"],
            nextYear: ["明年"],
            thisWeek: ["这周", "這週", "本周"],
            weekend: ["周末", "週末"],
            weekdays: [["星期日", "星期天", "周日", "週日"], ["星期一", "周一", "週一"],
                       ["星期二", "周二", "週二"], ["星期三", "周三", "週三"],
                       ["星期四", "周四", "週四"], ["星期五", "周五", "週五"],
                       ["星期六", "周六", "週六"]],
            morning: ["早上", "上午"],
            noon: ["中午"],
            afternoon: ["下午"],
            evening: ["晚上"],
            nightTime: ["今晚", "今夜"],
            midnight: ["午夜"],
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
            nextMonth: ["पुढच्या महिन्यात"],
            nextYear: ["पुढच्या वर्षी"],
            thisWeek: ["या आठवड्यात"],
            weekend: ["आठवड्याचा शेवट"],
            weekdays: [["रविवार"], ["सोमवार"], ["मंगळवार"], ["बुधवार"],
                       ["गुरुवार"], ["शुक्रवार"], ["शनिवार"]],
            morning: ["सकाळ"],
            noon: ["दुपार"],
            afternoon: ["दुपारनंतर"],
            evening: ["संध्याकाळ"],
            nightTime: ["आज रात्री", "रात्र"],
            midnight: ["मध्यरात्र"],
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
            nextMonth: ["వచ్చే నెల"],
            nextYear: ["వచ్చే సంవత్సరం"],
            thisWeek: ["ఈ వారం"],
            weekend: ["వారాంతం"],
            weekdays: [["ఆదివారం"], ["సోమవారం"], ["మంగళవారం"], ["బుధవారం"],
                       ["గురువారం"], ["శుక్రవారం"], ["శనివారం"]],
            morning: ["ఉదయం"],
            noon: ["మధ్యాహ్నం"],
            afternoon: ["సాయంత్రం"],
            evening: ["సాయంకాలం"],
            nightTime: ["ఈ రాత్రి", "రాత్రి"],
            midnight: ["అర్ధరాత్రి"],
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
            nextMonth: ["gelecek ay", "önümüzdeki ay", "onumuzdeki ay"],
            nextYear: ["gelecek yıl", "gelecek yil"],
            thisWeek: ["bu hafta"],
            weekend: ["hafta sonu"],
            weekdays: [["pazar"], ["pazartesi"], ["salı", "sali"], ["çarşamba", "carsamba"],
                       ["perşembe", "persembe"], ["cuma"], ["cumartesi"]],
            months: [["ocak"], ["şubat", "subat"], ["mart"], ["nisan"], ["mayıs", "mayis"],
                     ["haziran"], ["temmuz"], ["ağustos", "agustos"], ["eylül", "eylul"],
                     ["ekim"], ["kasım", "kasim"], ["aralık", "aralik"]],
            morning: ["sabah"],
            noon: ["öğle", "ogle"],
            afternoon: ["öğleden sonra", "ogleden sonra"],
            evening: ["akşam", "aksam"],
            nightTime: ["bu gece", "bu akşam"],
            midnight: ["gece yarısı", "gece yarisi"],
            daily: ["günlük", "gunluk", "her gün", "her gun"],
            weekly: ["haftalık", "haftalik", "her hafta"],
            monthly: ["aylık", "aylik", "her ay"],
            weekdaysRecur: ["hafta içi", "hafta ici"],
            every: ["her"],
            after: ["sonra"],
            dayUnit: ["gün", "gun", "günde", "gunde"],
            weekUnit: ["hafta"],
            monthUnit: ["ay"],
            yearUnit: ["yıl", "yil"],
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
            nextMonth: ["அடுத்த மாதம்"],
            nextYear: ["அடுத்த ஆண்டு"],
            thisWeek: ["இந்த வாரம்"],
            weekend: ["வார இறுதி"],
            weekdays: [["ஞாயிறு"], ["திங்கள்"], ["செவ்வாய்"], ["புதன்"],
                       ["வியாழன்"], ["வெள்ளி"], ["சனி"]],
            morning: ["காலை"],
            noon: ["மதியம்"],
            afternoon: ["பிற்பகல்"],
            evening: ["மாலை"],
            nightTime: ["இன்றிரவு", "இரவு"],
            midnight: ["நள்ளிரவு"],
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
            nextMonth: ["tháng sau", "tháng tới"],
            nextYear: ["năm sau", "năm tới"],
            thisWeek: ["tuần này"],
            weekend: ["cuối tuần"],
            weekdays: [["chủ nhật"], ["thứ hai"], ["thứ ba"], ["thứ tư"],
                       ["thứ năm"], ["thứ sáu"], ["thứ bảy"]],
            morning: ["buổi sáng", "sáng"],
            noon: ["buổi trưa", "trưa"],
            afternoon: ["buổi chiều", "chiều"],
            evening: ["buổi tối", "tối"],
            nightTime: ["tối nay"],
            midnight: ["nửa đêm"],
            daily: ["hằng ngày", "hàng ngày", "mỗi ngày"],
            weekly: ["hằng tuần", "hàng tuần"],
            monthly: ["hằng tháng", "hàng tháng"],
            weekdaysRecur: ["ngày thường"],
            every: ["mỗi"],
            within: ["trong", "sau"],
            dayUnit: ["ngày"],
            weekUnit: ["tuần"],
            monthUnit: ["tháng"],
            yearUnit: ["năm"],
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
            nextMonth: ["다음 달", "다음달"],
            nextYear: ["내년"],
            thisWeek: ["이번 주", "이번주"],
            weekend: ["주말"],
            weekdays: [["일요일"], ["월요일"], ["화요일"], ["수요일"],
                       ["목요일"], ["금요일"], ["토요일"]],
            morning: ["아침", "오전"],
            noon: ["정오"],
            afternoon: ["오후"],
            evening: ["저녁"],
            nightTime: ["오늘 밤", "밤"],
            midnight: ["자정"],
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
            nextMonth: ["ماه بعد", "ماه آینده"],
            nextYear: ["سال بعد", "سال آینده"],
            thisWeek: ["این هفته"],
            weekend: ["آخر هفته"],
            weekdays: [["یکشنبه"], ["دوشنبه"], ["سه‌شنبه", "سه شنبه"], ["چهارشنبه"],
                       ["پنجشنبه", "پنج‌شنبه"], ["جمعه"], ["شنبه"]],
            morning: ["صبح"],
            noon: ["ظهر"],
            afternoon: ["بعد از ظهر"],
            evening: ["عصر", "غروب"],
            nightTime: ["امشب", "شب"],
            midnight: ["نیمه شب"],
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
            nextMonth: ["prossimo mese", "mese prossimo"],
            nextYear: ["prossimo anno", "anno prossimo"],
            thisWeek: ["questa settimana"],
            weekend: ["fine settimana", "weekend"],
            weekdays: [["domenica"], ["lunedì", "lunedi"], ["martedì", "martedi"],
                       ["mercoledì", "mercoledi"], ["giovedì", "giovedi"],
                       ["venerdì", "venerdi"], ["sabato"]],
            months: [["gennaio"], ["febbraio"], ["marzo"], ["aprile"], ["maggio"], ["giugno"],
                     ["luglio"], ["agosto"], ["settembre"], ["ottobre"], ["novembre"], ["dicembre"]],
            morning: ["mattina", "stamattina"],
            noon: ["mezzogiorno"],
            afternoon: ["pomeriggio"],
            evening: ["sera", "stasera"],
            midnight: ["mezzanotte"],
            daily: ["giornaliero", "quotidiano", "ogni giorno"],
            weekly: ["settimanale", "ogni settimana"],
            monthly: ["mensile", "ogni mese"],
            weekdaysRecur: ["giorni feriali"],
            every: ["ogni"],
            within: ["tra", "fra"],
            dayUnit: ["giorno", "giorni"],
            weekUnit: ["settimana", "settimane"],
            monthUnit: ["mese", "mesi"],
            yearUnit: ["anno", "anni"],
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
            nextMonth: ["wata mai zuwa"],
            nextYear: ["shekara mai zuwa"],
            thisWeek: ["wannan mako"],
            weekend: ["karshen mako"],
            weekdays: [["lahadi"], ["litinin"], ["talata"], ["laraba"],
                       ["alhamis"], ["jumma'a"], ["asabar"]],
            morning: ["safe", "da safe"],
            noon: ["tsakar rana"],
            afternoon: ["yamma"],
            evening: ["maraice"],
            nightTime: ["yau da dare", "dare"],
            midnight: ["tsakar dare"],
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
            nextMonth: ["mwezi ujao"],
            nextYear: ["mwaka ujao"],
            thisWeek: ["wiki hii"],
            weekend: ["wikendi"],
            weekdays: [["jumapili"], ["jumatatu"], ["jumanne"], ["jumatano"],
                       ["alhamisi"], ["ijumaa"], ["jumamosi"]],
            morning: ["asubuhi"],
            noon: ["adhuhuri"],
            afternoon: ["alasiri"],
            evening: ["jioni"],
            nightTime: ["usiku huu", "usiku"],
            midnight: ["usiku wa manane"],
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
            nextMonth: ["ਅਗਲੇ ਮਹੀਨੇ"],
            nextYear: ["ਅਗਲੇ ਸਾਲ"],
            thisWeek: ["ਇਸ ਹਫ਼ਤੇ"],
            weekend: ["ਹਫ਼ਤੇ ਦਾ ਅੰਤ"],
            weekdays: [["ਐਤਵਾਰ"], ["ਸੋਮਵਾਰ"], ["ਮੰਗਲਵਾਰ"], ["ਬੁੱਧਵਾਰ"],
                       ["ਵੀਰਵਾਰ"], ["ਸ਼ੁੱਕਰਵਾਰ"], ["ਸ਼ਨਿੱਚਰਵਾਰ"]],
            morning: ["ਸਵੇਰ"],
            noon: ["ਦੁਪਹਿਰ"],
            afternoon: ["ਤੀਜਾ ਪਹਿਰ"],
            evening: ["ਸ਼ਾਮ"],
            nightTime: ["ਅੱਜ ਰਾਤ", "ਰਾਤ"],
            midnight: ["ਅੱਧੀ ਰਾਤ"],
            daily: ["ਰੋਜ਼ਾਨਾ", "ਹਰ ਰੋਜ਼"],
            weekly: ["ਹਫ਼ਤਾਵਾਰ"],
            monthly: ["ਮਹੀਨਾਵਾਰ"],
            priorityHigh: ["ਜ਼ਰੂਰੀ", "ਅਹਿਮ"]
        ),
    ]
}
