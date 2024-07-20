import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

void main() {
  AwesomeNotifications().initialize(
    'resource://drawable/res_app_icon',
    [
      NotificationChannel(
        channelKey: 'scheduled',
        channelName: 'Scheduled Notifications',
        channelDescription: 'Channel for scheduled notifications',
        defaultColor: const Color(0xFF9D50DD),
        ledColor: Colors.white,
        importance: NotificationImportance.High,
        channelShowBadge: true,
      )
    ],
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Müllplan',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late SharedPreferences _prefs;
  late Color _selectedColor;
  Color? _userColor;
  TimeOfDay _selectedTime = TimeOfDay.now();
  List<int> _selectedDaysOfWeek = [];
  DateTime _focusedDay = DateTime.now();

  final List<Color> _colors = [
    Colors.orange,
    Colors.pink,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.red,
  ];

  final Map<Color, int> _colorNumbers = {
    Colors.orange: 62,
    Colors.pink: 63,
    Colors.yellow: 64,
    Colors.green: 65,
    Colors.blue: 66,
    Colors.red: 67,
  };

  @override
  void initState() {
    super.initState();
    _selectedColor = Colors.blue;
    _loadPreferences();
    _requestNotificationPermission();
  }

  void _requestNotificationPermission() async {
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    print("Notification permission status: $isAllowed");

    if (!isAllowed) {
      bool? result = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Allow notifications'),
          content: Text('This app requires permission to send notifications.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Yes'),
            ),
          ],
        ),
      );

      if (result != null && result) {
        AwesomeNotifications().requestPermissionToSendNotifications();
        print("Notification permission request initiated.");
      }
    }
  }

  void _loadPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    print("SharedPreferences loaded.");

    _loadTime();
    _loadDaysOfWeek();

    setState(() {
      int colorValue = _prefs.getInt('selected_color') ?? Colors.blue.value;
      _selectedColor = Color(colorValue);
      print("Loaded color: $_selectedColor");

      _userColor = (_prefs.getInt('user_color') != null) ? Color(_prefs.getInt('user_color')!) : null;
      print("Loaded user color: $_userColor");
    });
  }

  void _loadTime() {
    int hour = _prefs.getInt('hour') ?? TimeOfDay.now().hour;
    int minute = _prefs.getInt('minute') ?? TimeOfDay.now().minute;
    print("Loaded time: $hour:$minute");

    setState(() {
      _selectedTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  void _loadDaysOfWeek() {
    String? daysString = _prefs.getString('selected_days');
    if (daysString != null) {
      _selectedDaysOfWeek = daysString.split(',').map(int.parse).toList();
    }
    print("Loaded days of week: ${_selectedDaysOfWeek.join(',')}");
  }

  void _saveTime(TimeOfDay time) async {
    await _prefs.setInt('hour', time.hour);
    await _prefs.setInt('minute', time.minute);
    await _prefs.setString('selected_days', _selectedDaysOfWeek.join(','));
    print("Saved time: ${time.hour}:${time.minute} and days: ${_selectedDaysOfWeek.join(',')}");
  }

  void _pickTime() async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (pickedTime != null) {
      print("Picked time: ${pickedTime.hour}:${pickedTime.minute}");

      showDialog(
        context: context,
        builder: (context) {
          List<int> localSelectedDaysOfWeek = List.from(_selectedDaysOfWeek);

          return AlertDialog(
            title: const Text('Choose Weekday'),
            content: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(7, (index) {
                    int dayOfWeek = index + 1;
                    return CheckboxListTile(
                      title: Text(_getDayName(dayOfWeek)),
                      value: localSelectedDaysOfWeek.contains(dayOfWeek),
                      onChanged: (bool? isChecked) {
                        setState(() {
                          if (isChecked == true) {
                            localSelectedDaysOfWeek.add(dayOfWeek);
                          } else {
                            localSelectedDaysOfWeek.remove(dayOfWeek);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              },
            ),
            actions: [
              TextButton(
                child: const Text('Abort'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: const Text('Okay'),
                onPressed: () {
                  setState(() {
                    _selectedTime = pickedTime;
                    _selectedDaysOfWeek = localSelectedDaysOfWeek;
                  });
                  _saveTime(pickedTime);
                  _scheduleNotificationForColorMatch(pickedTime);
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  void _scheduleNotificationForColorMatch(TimeOfDay time) async {
    List<int> notificationIds = _prefs.getStringList('notification_ids')?.map(int.parse).toList() ?? [];

    // Alte Benachrichtigungen löschen
    for (int id in notificationIds) {
      await AwesomeNotifications().cancel(id);
      print("Old notification with ID $id canceled.");
    }

    DateTime now = DateTime.now();
    Color weekColor = _getWeekColor(now);

    int userColorIndex = _colors.indexOf(_userColor ?? Colors.transparent);
    int weekColorIndex = _colors.indexOf(weekColor);

    int weeksDelay = (userColorIndex - weekColorIndex + _colors.length) % _colors.length;
    DateTime firstNotificationDate = now.add(Duration(days: weeksDelay * 7));

    List<int> newNotificationIds = [];

    // Erste Benachrichtigung planen
    for (int dayOfWeek in _selectedDaysOfWeek) {
      int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      newNotificationIds.add(id);

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: 'scheduled',
          title: 'Trash-Time',
          body: "It's your turn to take out the trash. Thank you!",
        ),
        schedule: NotificationCalendar(
          year: firstNotificationDate.year,
          month: firstNotificationDate.month,
          day: firstNotificationDate.day,
          weekday: dayOfWeek,
          hour: time.hour,
          minute: time.minute,
          second: 0,
          millisecond: 0,
          repeats: false,
        ),
      ).then((_) {
        print("First notification scheduled with $weeksDelay weeks delay.");
      }).catchError((error) {
        print("Error scheduling first notification: $error");
      });
    }

    // Alle weiteren Benachrichtigungen in 6-Wochen-Intervallen planen
    await _scheduleRecurringNotifications(time, newNotificationIds, firstNotificationDate);

    await _prefs.setStringList('notification_ids', newNotificationIds.map((id) => id.toString()).toList());
  }

  Future<void> _scheduleRecurringNotifications(TimeOfDay time, List<int> newNotificationIds, DateTime startDate) async {
    DateTime nextNotificationDate = startDate.add(Duration(days: 6 * 7)); // 6 Wochen nach dem Startdatum

    for (int i = 0; i < 36; i++) { // Äußere Schleife für insgesamt 36 Benachrichtigungen
      for (int dayOfWeek in _selectedDaysOfWeek) {
        int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
        newNotificationIds.add(id);

        // Debug-Ausgabe des geplanten Benachrichtigungsdatums
        print("Scheduling notification with ID $id for date: $nextNotificationDate");

        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: id,
            channelKey: 'scheduled',
            title: 'Trash-Time',
            body: "It's your turn to take out the trash. Thank you!",
          ),
          schedule: NotificationCalendar(
            year: nextNotificationDate.year,
            month: nextNotificationDate.month,
            day: nextNotificationDate.day,
            weekday: dayOfWeek,
            hour: time.hour,
            minute: time.minute,
            second: 0,
            millisecond: 0,
            repeats: false,
          ),
        ).then((_) {
          print("Notification scheduled for $nextNotificationDate.");
        }).catchError((error) {
          print("Error scheduling notification: $error");
        });

        // Nächstes Benachrichtigungsdatum auf 6 Wochen verschieben
        nextNotificationDate = nextNotificationDate.add(Duration(days: 6 * 7));
      }
    }

    await _prefs.setStringList('notification_ids', newNotificationIds.map((id) => id.toString()).toList());
  }




  Color _getWeekColor(DateTime date) {
    DateTime mondayOfCurrentWeek = date.subtract(Duration(days: date.weekday - 1));
    DateTime startDate = DateTime(2024, 7, 7);
    DateTime startMonday = startDate.subtract(Duration(days: startDate.weekday - 1));
    int weeksPassed = mondayOfCurrentWeek.difference(startMonday).inDays ~/ 7;
    Color weekColor = _colors[weeksPassed % _colors.length];
    print("Week color for ${date.toLocal()}: $weekColor");
    return weekColor;
  }

  String _getDayName(int dayOfWeek) {
    switch (dayOfWeek) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }

  void _selectUserColor(Color? color) async {
    setState(() {
      _userColor = color;
    });
    if (color != null) {
      await _prefs.setInt('user_color', color.value);
      print("User color set to: $color");
    } else {
      await _prefs.remove('user_color');
      print("User color removed.");
    }
  }

  void _showApartmentSelectionDialog() async {
    Color? selectedColor;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Apartment'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: _colors.map((color) {
                  return RadioListTile<Color>(
                    title: Text('Apartment ${_colorNumbers[color]}'),
                    value: color,
                    groupValue: selectedColor,
                    onChanged: (Color? value) {
                      setState(() {
                        selectedColor = value;
                      });
                    },
                    activeColor: color,
                  );
                }).toList(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (selectedColor != null) {
                  _selectUserColor(selectedColor);
                  _pickTime();
                }
              },
              child: Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Müllplan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.access_time),
            onPressed: _showApartmentSelectionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _focusedDay = DateTime.now();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 1, 1),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleTextStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                formatButtonTextStyle: TextStyle(fontSize: 14.0),
                leftChevronIcon: Icon(Icons.chevron_left),
                rightChevronIcon: Icon(Icons.chevron_right),
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, date, focusedDay) {
                  Color weekColor = _getWeekColor(date);
                  return Container(
                    margin: const EdgeInsets.all(4.0),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: weekColor.withOpacity(date.weekday == 7 ? 1 : 0.3),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            '${date.day}',
                            style: TextStyle(color: date.weekday == 7 ? Colors.white : Colors.black),
                          ),
                        ),
                        if (date.weekday == 7)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2.0, top: 0.0),
                              child: Text(
                                '${_colorNumbers[weekColor]}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
              headerVisible: true,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 0.0, right: 16.0),
          ),
        ],
      ),
    );
  }
}
