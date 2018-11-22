#  Заметки
## Идеи
### Добавить описание 
Learn words makes use of system voices. The  standart quality is good enough, but there are rich options to choose from.
You can install adiditonal voices of higher quality and choose on your taste. 
This is done through Settings > General > Accessibility > VoiceOver > Speech
https://support.apple.com/en-us/HT202362


## Журнал
22.10.19 14:30
Добавлены настройки через стандарный интерфейс Settings программ в iOS.
Очень просто. Заодно опробованы возможности предзагрузки значений по-умолчанию, сохранение. Но это всё не потребовалось.
https://stackoverflow.com/questions/24045570/how-do-i-get-a-plist-as-a-dictionary-in-swift
Нужно разобраться с domens and suites. 
Подсказка:    вероятнее всего UserDefaults.standard = UserDefaults(suiteName: Bundle.main.bundleIdentifier) иначе откуда такая ошибка  //NSUserDefaults_Log_Nonsensical_Suites (suiteName: Bundle.main.bundleIdentifier)
Хороший пример (сброс настроек):
https://medium.com/@abhimuralidharan/adding-settings-to-your-ios-app-cecef8c5497

22.10.19 18:30
Боролся со странным багом виджете связанным с обновлением данных и вот этой штукой:
if let defaults = UserDefaults(suiteName: "group.club.laconic.LearnWords") 
В результате сейчас всё избыточно и неоптимально
В ре
