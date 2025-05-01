#  Заметки
## Идеи

### Сброс изученности слова
Реализовано свайпом вправо
Надо бы сбрасывать статистику всех слов в целых наборах, возможно, тоже свайпом вправо. 

### Озвучивание слов в списке
Сейчас вместе с исчезанием, показом перевода, но это не окончательный вариант

### Обработка long press
Еще не придумано действие, но что-то должно быть.
Возможно, контекстное меню с несколькими действиями

### Autoplay в режиме изучения.
И/или в режиме списка слов с подсветкой строки

### В share action, если слово одно сразу автоматически переходить в основную программу

### Добавить описание 
Learn words makes use of system voices. The  standart quality is good enough, but there are rich options to choose from.
You can install adiditonal voices of higher quality and choose on your taste. 
This is done through Settings > General > Accessibility > VoiceOver > Speech
https://support.apple.com/en-us/HT202362
Три кнопки в ряд и использовать пиктограммы вместо текста 

## TODO
05.10.19
Генерацию всех Locale и соответсвующих флагов для настроек.

08.07.20
Импорт текста словаря через Action Extension. Предусмотреть разные разделители, выбор разделителя.

Прописать процедуру первого запуска
https://developer.apple.com/documentation/uikit/app_and_environment/responding_to_the_launch_of_your_app/performing_one-time_setup_for_your_app
Внимание: для групповых файлов (`containerURL(forSecurityApplicationGroupIdentifier:)`) нужно создать директорию: https://developer.apple.com/documentation/foundation/filemanager/1412643-containerurl
См. проект Code/ViewsAndControllers/ActionExtensionFinal/Bookmark/Bookmark.xcodeproj.

Добавить произношение из widget-а. Например, long press на слове или переводе.
В краткой версии widget-а дать интерфейс добавления слова.

02.05.21 
Словарь противоположного направления (в обратную сторону):
https://pythonworld.ru/primery-programm/zadacha-pro-slovar.html
Заготовка reverse_dictionary.playground

08.05.21
Клавиатура, в которой только нужные символы
https://github.com/isaced/ISEmojiView

28.05.21
Импортирование содержимого буфера в качестве массива слов.
..Code/Dictionary/Kotoba-master/code/Kotoba.xcodeproj
Там же: icloud, импорт из текстовых файлов

07.06.21
Больше действий над строкой таблицы
https://useyourloaf.com/blog/table-swipe-actions/
Например, сброс статистики набора.
Редактирование слова или названия набора

10.07.21
Структуру БД заложить. Сделать все поля кроме основных опциональными для дальнейшей совместимости?
Или хотя алерт с предложением экспортировать-импортировать

Алерт при сегвее на Упражнение, если "В наборе нет слов для отображения" "Чтобы отображать выученные слова взведите соответсвующую опцию на экране Упражнения".

Настраиваемый порог изученности (количество узнаваний слова)

При импорте удаление дубликатов



Схема БД
https://stackoverflow.com/questions/16914185/how-to-design-a-database-for-translation-dictionary

Singleton, FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:
..Code/ViewsAndControllers/ActionExtensionFinal/Bookmark/

Распознание импортируемого текста на слова, если все слова на одном языке. Иначе распознавать как словарь. 

## Журнал
27.04.25
Добавлена настройка: количество успешных повторений, чтобы слово считалось изученным.
Короткий тап на ячейке в списке слов озвучивает слово.
Длинный – открывает системный словарь.

26.04.26
`UIReferenceLibraryViewController` теперь показывается в контроллере swipe to dissmiss с пользовательскими detents чтобы легче было смахивать вниз его. Можно тапнуть вне него и он тоже скроется. Эта фича работает с iOS16.
Добавлен сброс статистики для каждого слова (в таблице слов) чтобы можно было сбросить счётчик и таким образом перевести слово в разряд неизученных.
Усовершенствована работа с озвучкой. Благодаря тому, что не позволяется слишком часто дёргать TTS, он не отваливается, не замолкает.
25.04.25
Уход от hardcoded bundle id для App group.
Должно упростить запуск с различными Developer IDs. Но пока сделано неудачно.
22.11.18 14:30
Добавлены настройки через стандартный интерфейс Settings программ в iOS.
Очень просто. Заодно опробованы возможности предзагрузки значений по-умолчанию, сохранение. Но это всё не потребовалось.
https://stackoverflow.com/questions/24045570/how-do-i-get-a-plist-as-a-dictionary-in-swift
Нужно разобраться с domens and suites. 
Подсказка:    вероятнее всего UserDefaults.standard = UserDefaults(suiteName: Bundle.main.bundleIdentifier) иначе откуда такая ошибка  //NSUserDefaults_Log_Nonsensical_Suites (suiteName: Bundle.main.bundleIdentifier)
Хороший пример (сброс настроек):
https://medium.com/@abhimuralidharan/adding-settings-to-your-ios-app-cecef8c5497

22.11.18 18:30
Боролся со странным багом виджете связанным с обновлением данных и вот этой штукой:
if let defaults = UserDefaults(suiteName: "group.club.laconic.LearnWords") 
В результате сейчас всё избыточно и неоптимально

24.11.18 14:30
Выяснилось, что Settings.bundle только отрисовывает в панели системных настроек. При первом запуске ничего не записывает  БД, хотя если настройки изменились с панели, то тогда да - в перситент.
Есть специальный  метод register(defaults). Его надо вручную вызывать. Тогда в настройках возникает domain для fallback, но это не persistent storage.
Реализован изящный механизм, встроенный в инициализатор класса, синхронизирующий fallback defaults с root.plist (из Settings.bundle).
А если что-то записано в персистент, то оно имеет приоритет.
Выяснилось, что standard и site  - это разные settings, но оба они fallback to registered(defaults).
Найден скрытый, но рабочий RadioButton

Чтобы уведомлять программу об изменении настроек реализован наблюдатель NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification. Сейчас он во viewDidAppear главного controllera, чтобы не тормозить появление первого экрана.

25.11.18 14:00
Код модели перенесён в WordsModel. Пока не полностью, но уже намного лучше.
В процессе поиска причин предупреждения:
First responder warning: '; layer = ; contentOffset: {0, 0}; contentSize: {302, 20}; adjustedContentInset: {0, 0, 0, 0}>' rejected resignFirstResponder when being removed from hierarchy
Выяснилось, что надо обращать внимание на настройки tableView,
а также на свойства disablesAutomaticKeyboardDismissal, canResignFirstResponer по аналогии с canBecomeFirst responder.
Обнаружены другие методы
https://roadfiresoftware.com/2015/01/the-easy-way-to-dismiss-the-ios-keyboard/

26.11.18 14:00
SearchViewController.swift теперь обходится одним лишь seachBar без ViewController. Значительное упрощение с точки зрения архитектуры. Побежден баг связанный с инициализатором UISearchBar(frame). При инициализации вызывается SizeToFit и только тогда дальше уже работает Autolayout. На objective-C точно такой же код работал сразу.
Заодно стала ясна классическая схема использования отдельного Search Controller благодяря примеру от Apple.
Это нечто, что модально накрывает основный UI. Есть тонкость с definesPresentationContext.
Для новой конструкции устанавливается primaryInputLanguage - аналогично тому, как это делалось при наличии search controller. 
Улучшена работа с Range, NSRange и тесты продолжаются (подбор слов).

06.12.18
Есть идея использовать:
class func preferredFontDescriptor(withTextStyle: UIFont.TextStyle, compatibleWith: UITraitCollection?) -> UIFontDescriptor
Returns a font descriptor containing the text style and the content size category specified by the provided trait collection.
Сразу нужный размер в зависимости от текущего размера View

07.12.18
Добавлена цветовая подсветка части искомого слова, всё благодаря изучению Range и NSRange.

05.10.19
Более логичная работа с NSRange - почти все ухищрения заменены нормальными стандартными средствами.

08.07.20
Все UserDefaults теперь групповые: UserDefaults(suiteName: "group.club.laconic.LearnWords")

16.10.20
Добавлены догадки в список предлагаемых слов, но пока закоментарены

4.06.21
Добавлен импорт словарей и отдельных единичных слов.


## Сырые мысли
Спорные идеи
 При первом запуске создаётся профиль пользователя: родной язык - изучаемый язык. В дальнейшем такой можно создавать ещё профили. Минус этой идеи то, что языки - это характеристика сета. Взято из MemoWord.

Два режима: учение и самопроверка. Учение: текст, на слух - затем определение и термин визуально, на слух все. Самопроверка - аналогично  
Хорошие идеи
 Одному слову термину может соответствовать несколько определений. При тестировании любое из определений генерирует верный ответ, равно как несколько определений через разделитель (,;).

Использовать haptic для ошибок 


 Показывать кнопку получения слов из буфера обмена на экране добавления слова. 


Передавать словари или слова при помощи action extension FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.appcoda.Bookmark"
Как в проекте Bookmarks   Разобраться с записью в общий для программы её расширения файл или в UserDefaults.
Упражнение - озвучить слово - фонетика, произношение.

## Известные баги
На iPad поворачивается
Не удаляет слово из набора
