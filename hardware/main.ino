#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- Hardware Pin Definitions ---
const int BUTTON_PIN = 25;  // Moved to safe pin 25
const int LED_PIN = 14;     // Moved to safe pin 14
const int BUZZER_PIN = 27;  // Moved to safe pin 27

// --- BLE UUIDs ---
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// --- Global State Variables ---
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
bool sosActive = false;

// --- Timing Variables ---
unsigned long buttonPressTime = 0;
bool isPressing = false;
const unsigned long SOS_TRIGGER_TIME = 2000;      // 2 seconds to trigger SOS
const unsigned long DISCONNECT_TRIGGER_TIME = 10000; // 10 seconds to force unpair

// --- Buzzer PWM Settings (Updated for ESP32 Core 3.x) ---
const int BUZZER_FREQ = 2500; // 2500 Hz gives a sharp, piercing beep
const int BUZZER_RESOLUTION = 8; // 8-bit resolution (0-255)

// --- BLE Server Callbacks ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("STATUS: Smartphone Paired and Connected!");
    }
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("STATUS: Smartphone Disconnected.");
    }
};

void setup() {
  Serial.begin(115200);
  Serial.println("--- Booting SOS Keychain Prototype ---");

  // 1. Initialize Hardware Pins
  pinMode(BUTTON_PIN, INPUT_PULLUP); // Pin goes LOW when button is pressed
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // 2. Initialize PWM for Passive Buzzer (New ESP32 v3.x syntax)
  ledcAttach(BUZZER_PIN, BUZZER_FREQ, BUZZER_RESOLUTION);
  ledcWrite(BUZZER_PIN, 0); // Start silenced (0 duty cycle)

  // 3. Initialize BLE Environment
  BLEDevice::init("SOS_Keychain");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create the Characteristic (Phone will subscribe to this to get alerts)
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();

  // 4. Start Advertising BLE
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);  
  BLEDevice::startAdvertising();
  
  Serial.println("STATUS: BLE Advertising started. Waiting for connection...");
}

void loop() {
  int buttonState = digitalRead(BUTTON_PIN);
  unsigned long currentMillis = millis();

  // ==========================================
  // 1. BUTTON LOGIC (Timing & Triggers)
  // ==========================================
  
  // Detect Initial Button Press
  if (buttonState == LOW && !isPressing) {
    isPressing = true;
    buttonPressTime = currentMillis;
    Serial.println("EVENT: Button Pressed. Monitoring duration...");
  } 
  
  // Button is currently being held down
  else if (buttonState == LOW && isPressing) {
    unsigned long holdDuration = currentMillis - buttonPressTime;
    
    // TRIGGER 1: 2-Second Hold -> Activate SOS
    if (holdDuration >= SOS_TRIGGER_TIME && holdDuration < DISCONNECT_TRIGGER_TIME && !sosActive) {
      sosActive = true;
      Serial.println("***********************************");
      Serial.println("ALERT: 2-SECOND SOS TRIGGERED!");
      Serial.println("***********************************");
      
      // Push BLE Notification to the phone
      if (deviceConnected) {
        pCharacteristic->setValue("SOS_ALERT_TRIGGERED");
        pCharacteristic->notify();
        Serial.println("ACTION: BLE Alert sent to Smartphone.");
      } else {
        Serial.println("WARNING: No smartphone connected! Cannot send BLE alert.");
      }
    }
    
    // TRIGGER 2: 10-Second Hold -> Force Disconnect & Reset
    if (holdDuration >= DISCONNECT_TRIGGER_TIME) {
      Serial.println("EVENT: 10-Second Hold Detected.");
      Serial.println("ACTION: Forcing Disconnect and Resetting Device...");
      
      sosActive = false;           // Turn off alarms
      digitalWrite(LED_PIN, LOW);
      ledcWrite(BUZZER_PIN, 0);    // Updated for v3.x
      
      if (deviceConnected) {
         pServer->disconnect(pServer->getConnId());
      }
      
      // Wait in a blocking loop until the user physically lets go of the button
      Serial.println("STATUS: Please release the button...");
      while(digitalRead(BUTTON_PIN) == LOW) {
        delay(50); 
      }
      isPressing = false; 
      Serial.println("STATUS: Reset complete. Ready to pair to a new device.");
    }
  } 
  
  // Button Released
  else if (buttonState == HIGH && isPressing) {
    isPressing = false;
    unsigned long finalHoldDuration = currentMillis - buttonPressTime;
    
    Serial.print("EVENT: Button Released. Total hold time: ");
    Serial.print(finalHoldDuration);
    Serial.println(" ms");

    if (sosActive && finalHoldDuration < DISCONNECT_TRIGGER_TIME) {
      Serial.println("ACTION: Deactivating SOS Alarms.");
      sosActive = false;
      digitalWrite(LED_PIN, LOW);
      ledcWrite(BUZZER_PIN, 0); // Updated for v3.x
    }
  }

  // ==========================================
  // 2. HARDWARE BEHAVIOR (Flashing & Buzzing)
  // ==========================================
  
  if (sosActive) {
    // Non-blocking toggle every 200ms for a fast, urgent strobe effect
    if ((currentMillis / 200) % 2 == 0) { 
      digitalWrite(LED_PIN, HIGH);
      ledcWrite(BUZZER_PIN, 128); // Updated for v3.x: 50% duty cycle to generate tone
    } else {
      digitalWrite(LED_PIN, LOW);
      ledcWrite(BUZZER_PIN, 0);   // Updated for v3.x: Silence
    }
  }

  // ==========================================
  // 3. BLE CONNECTION MANAGEMENT
  // ==========================================
  
  // Handling disconnection
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      pServer->startAdvertising(); 
      Serial.println("STATUS: Advertising restarted. Ready for new connection.");
      oldDeviceConnected = deviceConnected;
  }
  // Handling connection
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }

  delay(20); // Small debounce delay
}