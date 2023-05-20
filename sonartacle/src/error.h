#pragma once
#include <JuceHeader.h>

#include <sstream>
#include <string>

class Error
{
 public:
  explicit Error(const std::string& msg) : err(true), message(msg) {}
  explicit Error(const juce::String& msg) : err(true), message(msg.toStdString()) {}
  explicit Error(const char* msg) : err(true), message(msg) {}
  explicit Error() : err(false) {}
  std::string what() const { return message; }

 public:
  friend std::ostream& operator<<(std::ostream& strm, const Error& e) { return strm << e.message; }
  explicit operator bool() const { return err; }
  explicit operator std::string() const { return what(); }
  explicit operator juce::String() const { return static_cast<juce::String>(message); }

 private:
  bool err;
  std::string message;
};
