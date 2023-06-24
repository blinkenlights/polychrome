#include "server.h"

#include <plog/Log.h>

#include <iostream>

namespace beak::net
{
Server::Server(asio::io_context &ioCtx, uint16_t port) :
  m_socket(ioCtx, udp::endpoint(udp::v4(), static_cast<asio::ip::port_type>(port)))
{
  startReceive();
}

void Server::startReceive()
{
  m_socket.async_receive_from(
      asio::buffer(m_recvBuffer), m_remoteEndpoint,
      std::bind(&Server::handleReceive, this, std::placeholders::_1, std::placeholders::_2));
}

void Server::handleReceive(const asio::error_code &error, std::size_t sz)
{
  if (!error)
  {
    std::shared_ptr<Packet> const packet(new Packet());
    if (!packet->ParseFromArray(&m_recvBuffer, static_cast<int>(sz)))
    {
      startReceive();
      return;
    }

    const Packet::ContentCase type = packet->content_case();
    if (!m_callBackFns.contains(type))
    {
      startReceive();
      return;
    }

    const msgRecvCallbackFn fn = m_callBackFns.at(packet->content_case());
    if (fn)
    {
      fn.operator()(packet);
    }
    startReceive();
  }
}

void Server::handleSend(std::shared_ptr<std::string> msg, const asio::error_code &error,
                        std::size_t /*bytes_transferred*/)
{
  PLOGD << "Sending '" << *msg << "', error: " << (error ? error.message() : "none");
}

void Server::send(std::shared_ptr<std::string> msg, std::size_t /*sz*/)
{
  m_socket.async_send_to(
      asio::buffer(*msg), m_remoteEndpoint,
      std::bind(&Server::handleSend, this, msg, std::placeholders::_1, std::placeholders::_2));
}

void Server::send(std::shared_ptr<Packet> packet, std::size_t /*sz*/)
{
  auto payload = std::make_shared<std::string>(packet->SerializeAsString());
  send(payload, static_cast<std::size_t>(packet->ByteSizeLong()));
}

void Server::registerCallback(Packet::ContentCase type, msgRecvCallbackFn fn)
{
  m_callBackFns[type] = fn;
}
}  // namespace beak::net
