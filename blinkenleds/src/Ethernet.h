#ifndef __ETHERNET_H_INCLUDED__
#define __ETHERNET_H_INCLUDED__

class Ethernet
{

public:
  static void setup();
  static void loop();
  static void remote_log(String message);
  static void send_firmware_info();

private:
};

#endif // __ETHERNET_H_INCLUDED__
