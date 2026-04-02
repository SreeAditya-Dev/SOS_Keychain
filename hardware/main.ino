#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- Pin Definitions ---
const int buzzerPin = 4;
const int buttonSOS = 15;   // Button 1: Hold 2 sec to trigger SOS
const int buttonCtrl = 5;   // Button 2: Stop alarm / Reset BLE
const int ledPin = 12;      // External LED indicator (Changed from 2 to avoid built-in LED)
                            // GPIO 2 is the built-in LED on most ESP32 boards
                            // Use GPIO 12, 13, 14, or 16 for external LED

// --- BLE UUIDs ---
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

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
      Serial.println("Phone Disconnected.");
    }
};

// --- BLE Characteristic Callbacks to handle writes from app ---
class MyCharacteristicCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue();
      
      if (value.length() > 0) {
        Serial.print("Received from app: ");
        Serial.println(value);
        
        // Handle CANCEL_SOS command from app
        if (value == "CANCEL_SOS") {
          if (isSOSActive) {
            isSOSActive = false;
            digitalWrite(ledPin, LOW);
            noTone(buzzerPin);
            digitalWrite(buzzerPin, LOW);
            Serial.println("SOS Cancelled via App Command.");
            
            // Notify app that SOS was cancelled
            pCharacteristic->setValue("SOS_CANCELLED");
            pCharacteristic->notify();
          }
        }
        // Handle PING command from app (for connection test)
        else if (value == "PING") {
          pCharacteristic->setValue("PONG");
          pCharacteristic->notify();
          Serial.println("Responded to PING with PONG");
        }
      }
    }
};

void startAdvertising() {
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // Helps with iPhone connection issues
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE Advertising started...");
}

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

  // Create characteristic with Read, Write, and Notify properties
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_WRITE_NR |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  // Set the callback to handle writes from app
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

  // Required for notifications to work in apps like nRF Connect
  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();
  
  // Start advertising
  startAdvertising();

  Serial.println("ESP32 Ready. BLE Advertising started as 'SOS_KEYCHAIN'.");
}

void loop() {
  // ==========================================
  // Handle BLE Connection State Changes
  // ==========================================
  // Disconnecting - restart advertising after a short delay
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // Give the BLE stack time to clean up
    startAdvertising();
    Serial.println("Restarted advertising after disconnect.");
    oldDeviceConnected = deviceConnected;
  }
  
  // Connecting
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

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
  // 2. Check Control Button (Button 2) - Stop / Reset BLE
  // ==========================================
  if (ctrlState == LOW) {
    if (isSOSActive) {
      // Stop SOS alarm
      isSOSActive = false;
      digitalWrite(ledPin, LOW);
      noTone(buzzerPin);
      digitalWrite(buzzerPin, LOW);
      Serial.println("SOS Cancelled via Button 2.");
      
      if (deviceConnected) {
        pCharacteristic->setValue("SOS_CANCELLED");
        pCharacteristic->notify();
      }
    } else {
      // If SOS is NOT active, use Button 2 to restart BLE advertising
      // This helps when the app can't find the device
      if (deviceConnected) {
        pServer->disconnect(pServer->getConnId());
        Serial.println("Forced BLE Disconnect via Button 2.");
      } else {
        // Restart advertising if not connected
        startAdvertising();
        Serial.println("Manually restarted BLE advertising via Button 2.");
      }
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