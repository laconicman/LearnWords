#  Заметки
## Идеи
### Добавить описание 
Learn words makes use of system voices. The  standart quality is good enough, but there are rich options to choose from.
You can install adiditonal voices of higher quality and choose on your taste. 
This is done through Settings > General > Accessibility > VoiceOver > Speech
https://support.apple.com/en-us/HT202362


## Журнал
22.11.18 14:30
Добавлены настройки через стандарный интерфейс Settings программ в iOS.
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
