#include <Arduino.h>
#include <schema.pb.h>
#include <Display.h>
#include <Network.h>

void setup()
{
  Serial.begin(115200);
  while (!Serial)
    ; // wait for serial attach

  Serial.println("Initializing...");
  Serial.flush();

  delay(50);

  Display::setup();
  Network::setup();

  Serial.println("Setup done");
}

void loop()
{
  Network::loop();
  Display::loop();
}
