#pragma once
#include <array>
#include <asio.hpp>

#include "proto.h"

using asio::ip::udp;
typedef std::function<void(std::shared_ptr<AudioPacket>)> msgRecvCallbackFn;
class Server
{
 public:
  Server(asio::io_context &ioCtx, uint16_t port);

 public:
  void send(std::shared_ptr<std::string> msg, std::size_t sz);
  void send(std::shared_ptr<Packet> msg, std::size_t sz);
  void registerCallback(AudioPacket::ContentCase type, msgRecvCallbackFn fn);

 private:
  void startReceive();
  void handleReceive(const asio::error_code &error, std::size_t bytesTransferred);
  void handleSend(std::shared_ptr<std::string> message, const asio::error_code &error,
                  std::size_t bytes_transferred);

 private:
  udp::socket m_socket;
  udp::endpoint m_remoteEndpoint;
  std::array<char, 1024> m_recvBuffer;
  std::map<AudioPacket::ContentCase, msgRecvCallbackFn> m_callBackFns;
};
