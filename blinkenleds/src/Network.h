#ifndef __NETWORK_H_INCLUDED__
#define __NETWORK_H_INCLUDED__

class Network
{

public:
  static void setup();
  static void loop();
  static void remote_log(String message);
  static void send_firmware_info();

private:
};

#endif // __NETWORK_H_INCLUDED__
