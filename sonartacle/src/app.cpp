#include "app.h"

#include "engine.h"
#include "resource.h"
#include "server.h"

MainApp::MainApp() : m_deviceManager(new juce::AudioDeviceManager())
{
  using namespace juce;
  juce::MessageManager::getInstance();
  // default device manager config
  m_deviceManager->initialiseWithDefaultDevices(2, 2);

  // declare commands to be used
  addHelpCommand("--help|-h", "Usage:", true);
  addVersionCommand("--version|-v", "Multi channel sampler 0.0.1");
  addCommand({
      "list-devices",
      "list-devices",
      "Lists available devices",
      "This command lists all available devices on your computer",
      [this]([[maybe_unused]] juce::ArgumentList const &args)
      {
        if (auto err = listDevices(); err)
        {
          juce::ConsoleApplication::fail(err.what());
        }
      },
  });
  addCommand({
      "play",
      "play",
      "Plays an audio file on a specified channel",
      "",
      [this](juce::ArgumentList const &args)
      {
        auto file = args.getExistingFileForOption("--file");
        auto channel = args.getValueForOption("--channel").getIntValue();
        auto device = args.getValueForOption("--device");
        auto outputs = args.getValueForOption("--outputs").getIntValue();

        Engine engine(m_deviceManager, device, outputs);
        if (auto err = engine.initialize(); err) fail(static_cast<juce::String>(err));

        if (auto err = engine.playSound(file, channel); err)
          juce::ConsoleApplication::fail(static_cast<juce::String>(err));
      },
  });
  addDefaultCommand({
      "run",
      "run",
      "Run the server",
      "",
      [this](juce::ArgumentList const &args)
      {
        auto port = args.getValueForOption("--port").getIntValue();

        Cache cache("/Users/lukas/tmp");
        cache.initialize();

        Engine sampler(m_deviceManager, "MacBook Pro Speakers", 2);

        if (auto err = sampler.initialize())
          juce::ConsoleApplication::fail(static_cast<juce::String>(err));
        try
        {
          asio::io_context ioCtx;
          Server server(ioCtx, port);
          server.registerCallback(
              AudioPacket::kPlayMessage,
              [&sampler, &cache](std::shared_ptr<AudioPacket> packet)
              {
                std::cout << "play message: " << std::endl;
                std::cout << "uri: " << packet->playmessage().uri() << " ";
                std::cout << "start: " << packet->playmessage().start();
                std::cout << std::endl;

                if (juce::File::isAbsolutePath(packet->playmessage().uri()))
                {  // is local file
                  auto file = juce::File(packet->playmessage().uri());
                  if (auto err = sampler.playSound(file, packet->playmessage().channel()))
                    std::cerr << err << std::endl;
                }
                else if (auto file = cache.get(packet->playmessage().uri());
                         file.has_value())
                {
                  if (auto err = sampler.playSound(file.value(),
                                                   packet->playmessage().channel()))
                    std::cerr << err << std::endl;
                }
                else
                {
                  std::cerr << "not an local or remote file" << std::endl;
                }
              });
          ioCtx.run();
        }
        catch (std::exception &e)
        {
          juce::ConsoleApplication::fail(e.what());
        }
      },
  });
}

MainApp::~MainApp()
{
  juce::MessageManager::deleteInstance();
  DeletedAtShutdown::deleteAll();
}

/* -------------------------------- commands -------------------------------- */
Error MainApp::listDevices() const
{
  juce::OwnedArray<juce::AudioIODeviceType> devTypes;
  m_deviceManager->createAudioDeviceTypes(devTypes);
  for (const auto &type : devTypes)
  {
    cout << "[[ " << type->getTypeName() << " ]]" << endl;
    type->scanForDevices();
    for (const auto &dev : type->getDeviceNames())
    {
      cout << "  - " << dev << endl;
    }
  }
  return Error();
}
