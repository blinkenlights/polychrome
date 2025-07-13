#include <Arduino.h>
#include <Proximity.h>
#include <Network.h>
#include <soc/gpio_struct.h>

// PINS
#define TRIG1_PIN 14
#define TRIG2_PIN 33

#define ECHO1_PIN 34
#define ECHO2_PIN 35

#define TRIGGER_FREQ_HZ 10   // 10Hz per sensor
#define PWM_RESOLUTION 16    // 16-bit resolution
#define TRIGGER_PULSE_DUTY 7 // duty: 7/65536 * 100ms = ~10µs pulse

// PWM CHANNELS
#define PWM_CHANNEL_1 0
#define PWM_CHANNEL_2 1

// SENSOR STATE MACHINE
enum SensorState
{
  IDLE,      // Waiting for echo to start
  MEASURING, // Echo started, waiting for it to end
  READY      // Measurement complete, ready to process
};

// MEASUREMENT DATA
struct SensorData
{
  unsigned long echoStartTime;
  unsigned long echoEndTime;
  SensorState state;
};

// GLOBAL STATE
static SensorData sensor1Data = {0, 0, IDLE};
static SensorData sensor2Data = {0, 0, IDLE};

// READINGS PER SECOND
static unsigned long readingCount = 0;
static unsigned long lastRateCalculationTime = 0;
static float currentReadingsPerSecond = 0.0;

// Echo interrupt handlers
void IRAM_ATTR echo1ISR()
{
  if (digitalRead(ECHO1_PIN) == HIGH)
  {
    sensor1Data.echoStartTime = micros();
    sensor1Data.state = MEASURING;
  }
  else if (sensor1Data.state == MEASURING)
  {
    sensor1Data.echoEndTime = micros();
    sensor1Data.state = READY;
  }
}

void IRAM_ATTR echo2ISR()
{
  if (digitalRead(ECHO2_PIN) == HIGH)
  {
    sensor2Data.echoStartTime = micros();
    sensor2Data.state = MEASURING;
  }
  else if (sensor2Data.state == MEASURING)
  {
    sensor2Data.echoEndTime = micros();
    sensor2Data.state = READY;
  }
}

void Proximity::setup()
{
  pinMode(TRIG1_PIN, OUTPUT);
  pinMode(TRIG2_PIN, OUTPUT);
  pinMode(ECHO1_PIN, INPUT);
  pinMode(ECHO2_PIN, INPUT);

  // Setup PWM for both sensors
  ledcSetup(PWM_CHANNEL_1, TRIGGER_FREQ_HZ, PWM_RESOLUTION);
  ledcSetup(PWM_CHANNEL_2, TRIGGER_FREQ_HZ, PWM_RESOLUTION);

  ledcAttachPin(TRIG1_PIN, PWM_CHANNEL_1);
  ledcAttachPin(TRIG2_PIN, PWM_CHANNEL_2);

  // Start PWM channels simultaneously
  ledcWrite(PWM_CHANNEL_1, TRIGGER_PULSE_DUTY);
  ledcWrite(PWM_CHANNEL_2, TRIGGER_PULSE_DUTY);

  // Invert polarity of second sensor for 180° phase shift
  // GPIO.func_out_sel_cfg[TRIG2_PIN].inv_sel = 1;

  // Interrupts for echo pins
  attachInterrupt(digitalPinToInterrupt(ECHO1_PIN), echo1ISR, CHANGE);
  attachInterrupt(digitalPinToInterrupt(ECHO2_PIN), echo2ISR, CHANGE);

  Serial.println("Proximity setup done. Sensor trigger frequency: " + String(TRIGGER_FREQ_HZ) + "Hz");
}

void processSensorReading(int sensorId, SensorData &sensorData)
{
  if (sensorData.state == READY)
  {
    unsigned long duration = sensorData.echoEndTime - sensorData.echoStartTime;
    float distance = duration * 0.34 / 2;

    Network::send_proximity_event(sensorId, distance);

    readingCount++;

    // Reset sensor data
    sensorData.state = IDLE;
  }
}

void Proximity::loop()
{
  // Process readings from both sensors
  processSensorReading(0, sensor1Data);
  processSensorReading(1, sensor2Data);

  // Calculate readings per second
  unsigned long currentTime = millis();
  if (currentTime - lastRateCalculationTime >= 1000)
  {
    float timeInterval = (currentTime - lastRateCalculationTime) / 1000.0;
    currentReadingsPerSecond = readingCount / timeInterval;
    readingCount = 0;
    lastRateCalculationTime = currentTime;
  }
}

float Proximity::getReadingsPerSecond()
{
  return currentReadingsPerSecond;
}