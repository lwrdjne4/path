import 'dart:async';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:core';
//import 'package:workmanager/workmanager.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/* @pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    FlutterTts voicePing = FlutterTts();
    int refreshTime = 10;
    bool triger = false;

    try {
      await voicePing.setLanguage("en-US");
      await voicePing.setVolume(0.1);
      await voicePing.setPitch(0.5);
      await voicePing.setSpeechRate(0.5);

      while (true) {
        await Future.delayed(Duration(seconds: refreshTime));
        await voicePing.speak("$refreshTime");

        if (_CraftyPathState.controller.hasListener) {
          debugPrint(
              "stream hash from background task: ${_CraftyPathState.controller.stream.hashCode}");
          _CraftyPathState.controller.add(triger = !triger);
        }
      }
    } catch (e) {
      debugPrint(e.toString());
      return Future.value(false);
    }
  });
} */

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CraftyPath());
  /*  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  Workmanager().registerOneOffTask("123", "taskName",
      constraints: Constraints(
          networkType: NetworkType.not_required, requiresBatteryNotLow: true)); */
}

class CraftyPath extends StatefulWidget {
  const CraftyPath({super.key});

  @override
  State<CraftyPath> createState() => _CraftyPathState();
}

enum ServicesUUID {
  first("00000001-4c45-4b43-4942-265a524f5453"),
  second("00000002-4c45-4b43-4942-265a524f5453"),
  third("00000003-4c45-4b43-4942-265a524f5453"),
  fourth("00000004-4c45-4b43-4942-265a524f5453");

  final String uuid;
  const ServicesUUID(this.uuid);
}

enum CharacteristicsUUID {
  temperature("00000011-4c45-4b43-4942-265a524f5453"), //R N
  setPoint("00000021-4c45-4b43-4942-265a524f5453"), //R W
  powerUuid("00000063-4c45-4b43-4942-265a524f5453"), // R N
  heaterOn("00000081-4c45-4b43-4942-265a524f5453"), // W
  heaterOff("00000091-4c45-4b43-4942-265a524f5453"), //W
  battery("00000041-4C45-4B43-4942-265A524F5453"); //R N( N not working)

  final String uuid;
  const CharacteristicsUUID(this.uuid);
}

class CraftyRotatedBox extends RotatedBox {
  final int id;
  const CraftyRotatedBox(
      {super.key,
      required super.quarterTurns,
      required this.id,
      required super.child});
}

class ChartData {
  ChartData(this.temp, this.time, this.battery);
  final int temp;
  final Duration time;
  final int battery;
}

class _CraftyPathState extends State<CraftyPath> {
  // #region Vars
  dynamic sessionTimer;
  dynamic periodicTimer;
  String deviceID = "";
  String deviceName = "";
  bool connected = false;
  bool isConnecting = false;
  int setPoint = 0;
  int temperature = 0;
  int batteryPercent = 0;
  int sliderCount = 7;
  double sliderDefaultValue = 160;
  double sesionTime = 300;
  Stopwatch sessionElapsedTime = Stopwatch();
  Stopwatch heaterElapsedTime = Stopwatch();
  List<double> slidersValues = [];
  List<Color> slidersColor = [];
  Color startStopBtnColor = Colors.transparent;
  String startStopBtnText = "Start path";
  bool sessionStarted = false;
  List<ChartData> tempList = [];
  bool permissionErr = false;
  FlutterTts tts = FlutterTts();

  // #endregion

// #region Methods

  void onTimerUpdate(Timer timer) {
    if (!sessionStarted) {
      timer.cancel();
      return;
    }

    if (timer.tick < slidersValues.length) {
      writeSetPoinFromSliders(timer.tick);
    }

    debugPrint("ontimerupdate");
  }

  void writeSetPoinFromSliders(int index) {
    slidersColor[index] = Colors.red;
    setState(() {});
    tts.speak("${slidersValues[index].toInt()}");
    var hexStr = (slidersValues[index].toInt() * 10).toRadixString(16);
    if (hexStr.length < 4) hexStr = "0$hexStr";
    hexStr = hexStr[2] + hexStr[3] + hexStr[0] + hexStr[1];

    UniversalBle.writeValue(
            deviceID,
            ServicesUUID.first.uuid,
            CharacteristicsUUID.setPoint.uuid,
            Uint8List.fromList(hex.decode(hexStr)),
            BleOutputProperty.withResponse)
        .then(
      (value) {
        UniversalBle.readValue(deviceID, ServicesUUID.first.uuid,
                CharacteristicsUUID.setPoint.uuid)
            .then(
          (val) {
            setPoint = readTemp(val);
            setState(() {});
          },
        );
      },
    );
  }

  void setHeaterState(bool state) {
    Uint8List zero = Uint8List.fromList([0, 0]);
    if (state) {
      UniversalBle.writeValue(
          deviceID,
          ServicesUUID.first.uuid,
          CharacteristicsUUID.heaterOn.uuid,
          zero,
          BleOutputProperty.withResponse);
    } else {
      UniversalBle.writeValue(
          deviceID,
          ServicesUUID.first.uuid,
          CharacteristicsUUID.heaterOff.uuid,
          zero,
          BleOutputProperty.withResponse);
    }
  }

  void starSession() {
    if (sessionTimer != null) {
      if (sessionTimer.isActive) {
        return;
      }
    }
    int updateTime = (sesionTime / sliderCount).round();
    periodicTimer =
        Timer.periodic(Duration(seconds: updateTime), onTimerUpdate);
    startStopBtnColor = Colors.red;
    startStopBtnText = "Stop path";
    sessionElapsedTime.start();
    sessionTimer = Timer(Duration(seconds: sesionTime.round()), startStopPath);
  }

  void stopSession() {
    startStopBtnColor = Colors.green;
    startStopBtnText = "Start path";
    sessionElapsedTime.reset();
    heaterElapsedTime.reset();
    WakelockPlus.disable();
    if (sessionTimer != null) {
      sessionTimer.cancel();
    }
    if (periodicTimer != null) {
      periodicTimer.cancel();
    }
    for (var i = 0; i < slidersColor.length; i++) {
      slidersColor[i] = Colors.blue;
    }
  }

  void startStopPath() {
    sessionStarted = !sessionStarted;

    setHeaterState(sessionStarted);

    if (!sessionStarted) {
      stopSession();
    } else {
      WakelockPlus.enable();
      heaterElapsedTime.start();
      tempList.clear();
      startStopBtnColor = Colors.orange.shade600;
      writeSetPoinFromSliders(0);
      if ((setPoint - temperature).abs() <= 5) {
        starSession();
      }
    }
    setState(() {});
  }

  int readTemp(Uint8List value) {
    var hex1 = value[1].toRadixString(16);
    var hex2 = value[0].toRadixString(16);
    if (hex1.length < 2) hex1 = "0$hex1";
    if (hex2.length < 2) hex2 = "0$hex2";
    var temp = int.parse(hex1 + hex2, radix: 16);
    temp = (temp / 10).round();
    return temp;
  }

  void onValueChange(
      String deviceId, String characteristicId, Uint8List value) async {
    if (characteristicId == CharacteristicsUUID.temperature.uuid) {
      temperature = readTemp(value);
      UniversalBle.readValue(deviceId, ServicesUUID.first.uuid,
              CharacteristicsUUID.setPoint.uuid)
          .then(
        (val) {
          setPoint = readTemp(val);

          UniversalBle.readValue(deviceId, ServicesUUID.first.uuid,
                  CharacteristicsUUID.battery.uuid)
              .then(
            (value) {
              batteryPercent = value[0];
            },
          );

          if (sessionStarted) {
            tempList.add(ChartData(
                temperature, heaterElapsedTime.elapsed, batteryPercent));

            if ((setPoint - temperature).abs() <= 5) {
              starSession();
            }
          }

          setState(() {});
        },
      );
      setState(() {});
    } else if (characteristicId == CharacteristicsUUID.battery.uuid) {
      batteryPercent = value[0];
      setState(() {});
    }
  }

  void onScanResult(BleDevice device) async {
    if (device.name.toString() != "STORZ&BICKEL" && !kIsWeb) {
      return;
    }
    deviceID = device.deviceId;
    deviceName = device.name.toString();

    setState(() {});
    debugPrint("onScanResult 1 stop before connect");
    await UniversalBle.stopScan().catchError((e) {
      debugPrint("onScanResult err: $e");
    });
    debugPrint(
        "onScanResult 2 try to connect to dev: ${device.name.toString()} ; ${device.deviceId} ;");
    await UniversalBle.connect(deviceID,
            connectionTimeout: const Duration(seconds: 30))
        .catchError((e) {
      debugPrint("onScanResult err: $e");
    });
  }

  void onConnectionChange(String deviceId, bool isConnected) async {
    connected = isConnected;
    if (isConnected) {
      startStopBtnColor = Colors.green;      

      debugPrint("onConnectionChange 1 try to discover");
      await UniversalBle.discoverServices(deviceId).onError((error, stackTrace) {
         debugPrint("onConnectionChange|discoverServices err: $error");
          isConnecting = false;
          connected = false;
          setState(() {});

         throw false;
      });

      //init read of temp
      var tempValue = await UniversalBle.readValue(deviceId,
          ServicesUUID.first.uuid, CharacteristicsUUID.temperature.uuid);
      temperature = readTemp(tempValue);
      //init read of setPoint
      var setPointValue = await UniversalBle.readValue(
          deviceId, ServicesUUID.first.uuid, CharacteristicsUUID.setPoint.uuid);
      setPoint = readTemp(setPointValue);

      var battery = await UniversalBle.readValue(
          deviceId, ServicesUUID.first.uuid, CharacteristicsUUID.battery.uuid);
      batteryPercent = battery[0];

      UniversalBle.onValueChange = onValueChange;
      debugPrint("onConnectionChange 2 try to subs");
      //subs to temp update
      await UniversalBle.setNotifiable(deviceId, ServicesUUID.first.uuid,
          CharacteristicsUUID.temperature.uuid, BleInputProperty.notification);
      //subs to battery update
      await UniversalBle.setNotifiable(deviceId, ServicesUUID.first.uuid,
          CharacteristicsUUID.battery.uuid, BleInputProperty.notification);
    }
    isConnecting = false;    
    setState(() {});
  }

  void scannBle() {
    debugPrint("scannBle 1");
    if (isConnecting) {
      return;
    }

    setState(() {
      connected = false;
      isConnecting = true;
    });

    debugPrint("scannBle 2");
    UniversalBle.onConnectionChange = onConnectionChange;
    UniversalBle.onScanResult = onScanResult;
    UniversalBle.timeout = const Duration(seconds: 30);

    if (kIsWeb) {
      debugPrint("scannBle 3 stop scan");
      UniversalBle.stopScan().then(
        (value) {
          debugPrint("scannBle 4 start scan");
          UniversalBle.startScan(
              scanFilter: ScanFilter(
            withNamePrefix: ["STORZ&BICKEL"],
            withServices: [
              ServicesUUID.first.uuid,
              ServicesUUID.second.uuid,
              ServicesUUID.third.uuid,
              ServicesUUID.fourth.uuid,
            ],
          )).onError(
            (error, stackTrace) {
              debugPrint("startScan onError: $error  \t\t${DateTime.now()}");
              isConnecting = false;
            },
          );
        },
      );
    } else if (Platform.isAndroid) {
      UniversalBle.stopScan().then((value) {
        UniversalBle.startScan();
      }).catchError((e) {
        debugPrint("ScanBLE err: $e");
      });
    }
  }

  // #endregion

  @override
  void initState() {
    for (var i = 0; i < sliderCount; i++) {
      if (slidersValues.elementAtOrNull(i) == null) {
        slidersValues.add(sliderDefaultValue);
        slidersColor.add(Colors.blue);
      }
    }
    super.initState();
    /*  debugPrint("stream hash from InitState: ${controller.stream.hashCode}");
    controller.stream.listen(
      (event) {
        event ? trigerColor = Colors.blue.shade900 : Colors.orange.shade900;
        setState(() {});
      },
    ); */

    tts = FlutterTts();
    tts.setLanguage("en-US");
    tts.setVolume(0.5);
    tts.setPitch(0.5);
    tts.setSpeechRate(0.5);

    checkPermissions();

    SharedPreferences.getInstance().then(
      (value) {
        for (var i = 0; i < slidersValues.length; i++) {
          slidersValues[i] =
              value.getDouble('slidersValues[$i]') ?? sliderDefaultValue;
        }
        setState(() {});
      },
    );
  }

  void checkPermissions() {
    if (!kIsWeb) {
      Permission.bluetoothScan.status.then(
        (value) async {
          if (!value.isGranted) {
            await Permission.bluetoothScan.request().then(
              (value) {
                value.isGranted ? permissionErr = false : permissionErr = true;
              },
            );
            await Permission.bluetoothConnect.request().then(
              (value) {
                value.isGranted ? permissionErr = false : permissionErr = true;
              },
            );
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!connected) startStopBtnColor = Colors.transparent;

    var slidersRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(
          flex: 2,
        ),
        for (var i = 0; i < sliderCount; i++) ...[
          const Spacer(
            flex: 1,
          ),
          Column(
            children: [
              Text(slidersValues.elementAt(i).round().toString()),
              CraftyRotatedBox(
                id: i,
                quarterTurns: 3,
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.shade700),
                      borderRadius: const BorderRadius.all(Radius.circular(5))),
                  child: Slider(
                    thumbColor: Colors.orange.shade600,
                    allowedInteraction: SliderInteraction.tapAndSlide,
                    activeColor: slidersColor.elementAt(i),
                    divisions: 10,
                    max: 210,
                    min: sliderDefaultValue,
                    value: slidersValues.elementAt(i),
                    onChanged: (value) async {
                      slidersValues[i] = value;
                      final prefs = await SharedPreferences.getInstance();
                      prefs.setDouble('slidersValues[$i]', slidersValues[i]);
                      setState(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
          const Spacer(
            flex: 1,
          ),
        ],
        const Spacer(
          flex: 2,
        ),
      ],
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,// Colors.orange.shade700,
          title: const Text("Crafty Path"),
          centerTitle: true,
        ),
        body: Column(
          children: [
            const SizedBox(height: 10),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const SizedBox(width: 20),
                        if (isConnecting) ...[
                          LoadingAnimationWidget.inkDrop(
                            color: Colors.orange.shade700,
                            size: 30,
                          )
                        ] else if (connected) ...[
                          const Icon(
                            Icons.bluetooth_connected_sharp,
                            color: Colors.green,
                          )
                        ] else
                          const SizedBox(width: 20)
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              deviceID,
                              style: TextStyle(color: Colors.orange.shade700),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              deviceName,
                              style: TextStyle(color: Colors.orange.shade700),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton(
                            onPressed: !connected
                                ? () {
                                    scannBle();
                                  }
                                : null,
                            child: const Text("Scan")),
                        const SizedBox(
                          width: 10,
                        )
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      "Temperature: $temperature C°",
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Battery: $batteryPercent %",
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "SetPoint: $setPoint C°",
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              ],
            ),
            Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange.shade700),
                    borderRadius: const BorderRadius.all(Radius.circular(15))),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Slider(
                      max: 600,
                      min: 150,
                      divisions: 45,
                      activeColor: sesionTime > 300
                          ? Colors.orange.shade700
                          : Colors.blue,
                      value: sesionTime,
                      onChanged: sessionStarted
                          ? null
                          : (value) {
                              setState(() {
                                sesionTime = value;
                              });
                            },
                    ),
                    Text("Sesion time: ${sesionTime.round()}s."),
                  ],
                )),
            SfCartesianChart(
              primaryXAxis: const NumericAxis(
                /* maximum: sesionTime,
                minimum: 0,
                interval: 60, */
                tickPosition: TickPosition.inside,
                majorTickLines:
                    MajorTickLines(color: Colors.grey, size: 10, width: 2),
                majorGridLines: MajorGridLines(
                  color: Colors.blueGrey,
                  width: 0,
                ),
                title: AxisTitle(text: "seconds"),
              ),
              primaryYAxis: const NumericAxis(
                maximum: 210,
                minimum: 100,
                interval: 11,
                title: AxisTitle(text: "C°"),
                tickPosition: TickPosition.inside,
                majorTickLines: MajorTickLines(
                  color: Colors.green,
                  size: 10,
                  width: 2,
                ),
                majorGridLines:
                    MajorGridLines(color: Colors.greenAccent, width: 0),
                labelPosition: ChartDataLabelPosition.outside,
              ),
              axes: const [
                NumericAxis(
                  opposedPosition: true,
                  name: "percent",
                  interval: 10,
                  minimum: 0,
                  maximum: 100,
                  title: AxisTitle(text: "%"),
                  tickPosition: TickPosition.inside,
                  majorTickLines: MajorTickLines(
                    color: Colors.orange,
                    size: 10,
                    width: 2,
                  ),
                  majorGridLines: MajorGridLines(
                    color: Colors.orangeAccent,
                    width: 0,
                  ),
                  labelPosition: ChartDataLabelPosition.outside,
                ),
              ],
              legend: const Legend(isVisible: true),
              series: <CartesianSeries<ChartData, num>>[
                LineSeries<ChartData, num>(
                  yAxisName: "percent",
                  name: "%",
                  color: Colors.orange,
                  xValueMapper: (datum, index) => datum.time.inSeconds,
                  yValueMapper: (datum, index) => datum.battery,
                  dataSource: tempList,
                ),
                LineSeries<ChartData, num>(
                  name: "C°",
                  color: Colors.green,
                  xValueMapper: (datum, index) => datum.time.inSeconds,
                  yValueMapper: (datum, index) => datum.temp,
                  dataSource: tempList,
                ),
              ],
            ),
            slidersRow,
            const SizedBox(
              height: 10,
            ),
            ElevatedButton(
              style: ButtonStyle(
                backgroundColor:
                    WidgetStatePropertyAll<Color>(startStopBtnColor),
              ),
              onPressed: connected ? startStopPath : null,
              child: Text(startStopBtnText),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
