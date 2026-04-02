#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- Pin Definitions ---
const int buzzerPin = 4;
const int buttonSOS = 15;   // Button 1: Hold 2 sec to trigger SOS
const int buttonCtrl = 5;   // Button 2: Stop alarm / Reset BLE
const int ledPin = 2;       // LED indicator

// --- BLE UUIDs ---
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

// --- State Variables ---
bool isSOSActive = false;
unsigned long sosButtonPressTime = 0;
bool sosButtonHeld = false;

unsigned long previousMillis = 0;
bool toggleState = false;

// --- BLE Callbacks to track connection ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Phone Connected via BLE!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Phone Disconnected. Restarting advertising...");
      BLEDevice::startAdvertising(); // Resume advertising so phone can reconnect
    }
};

void setup() {
  Serial.begin(115200);

  pinMode(buzzerPin, OUTPUT);
  pinMode(ledPin, OUTPUT);
  pinMode(buttonSOS, INPUT_PULLUP);
  pinMode(buttonCtrl, INPUT_PULLUP);

  // --- BLE Setup ---
  BLEDevice::init("SOS_KEYCHAIN");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create characteristic with Notify property
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  // Required for notifications to work in apps like nRF Connect
  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();
  
  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);
  BLEDevice::startAdvertising();

  Serial.println("ESP32 Ready. BLE Advertising started as 'SOS_KEYCHAIN'.");
}

void loop() {
  int sosState = digitalRead(buttonSOS);
  int ctrlState = digitalRead(buttonCtrl);

  // ==========================================
  // 1. Check SOS Button (Button 1) - 2 Sec Hold
  // ==========================================
  if (sosState == LOW && !sosButtonHeld) {
    sosButtonPressTime = millis();
    sosButtonHeld = true;
    delay(50); // Debounce
  } 
  else if (sosState == LOW && sosButtonHeld) {
    // If held for more than 2000ms (2 seconds) and SOS isn't already active
    if (millis() - sosButtonPressTime >= 2000 && !isSOSActive) {
      isSOSActive = true;
      Serial.println("🚨 SOS TRIGGERED! 🚨");
      
      // Send BLE Notification to phone if connected
      if (deviceConnected) {
        pCharacteristic->setValue("SOS_ALERT_TRIGGERED");
        pCharacteristic->notify();
        Serial.println("BLE Alert sent to phone!");
      } else {
        Serial.println("No phone connected via BLE to receive alert.");
      }
    }
  } 
  else if (sosState == HIGH && sosButtonHeld) {
    sosButtonHeld = false; // Reset tracker when button is released
    delay(50);
  }

  // ==========================================
  // 2. Check Control Button (Button 2) - Stop
  // ==========================================
  if (ctrlState == LOW) {
    if (isSOSActive) {
      isSOSActive = false;
      digitalWrite(ledPin, LOW);
      noTone(buzzerPin);
      digitalWrite(buzzerPin, LOW);
      Serial.println("SOS Cancelled via Button 2.");
      
      if (deviceConnected) {
        pCharacteristic->setValue("SOS_CANCELLED");
        pCharacteristic->notify();
      }
    } else if (deviceConnected) {
      // If SOS is NOT active, use Button 2 to force disconnect BLE
      pServer->disconnect(pServer->getConnId());
      Serial.println("Forced BLE Disconnect via Button 2.");
    }
    delay(300); // Heavy debounce to prevent spamming
  }

  // ==========================================
  // 3. Handle SOS Alarm Output (Non-Blocking)
  // ==========================================
  // We use millis() here instead of delay() so we can still read button presses!
  if (isSOSActive) {
    unsigned long currentMillis = millis();
    if (currentMillis - previousMillis >= 200) { // Toggle every 200ms
      previousMillis = currentMillis;
      toggleState = !toggleState;
      
      if (toggleState) {
        digitalWrite(ledPin, HIGH);
        tone(buzzerPin, 1000); // High pitch siren
      } else {
        digitalWrite(ledPin, LOW);
        tone(buzzerPin, 800);  // Low pitch siren
      }
    }
  }
}