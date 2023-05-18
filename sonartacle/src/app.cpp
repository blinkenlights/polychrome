#include "app.h"

#include "engine.h"
#include "resource.h"
#include "server.h"

MainApp::MainApp() : m_deviceManager(new juce::AudioDeviceManager())
{
  using namespace juce;
  juce::MessageManager::getInstance();

  // declare commands to be used
  addHelpCommand("--help|-h", "Usage:", true);
  addVersionCommand("--version|-v", "Multi channel sampler 0.0.1");
  addCommand({
      "list-devices",
      "list-devices",
      "Lists available devices",
      "This command lists all available devices on your computer",
      listCmd,
  });
  addCommand({
      "play",
      "play",
      "Plays an audio file on a specified channel",
      "",
      playCmd,
  });
  addDefaultCommand({
      "run",
      "run",
      "Runs the server",
      "This command runs a udp server with an protobuf api.",
      runCmd,
  });
}

MainApp::~MainApp()
{
  juce::MessageManager::deleteInstance();
  DeletedAtShutdown::deleteAll();
}

/* -------------------------------- commands -------------------------------- */
void MainApp::listCmd(juce::ArgumentList const & /*args*/)
{
  juce::OwnedArray<juce::AudioIODeviceType> devTypes;
  juce::AudioDeviceManager deviceManager;
  deviceManager.createAudioDeviceTypes(devTypes);
  for (const auto &type : devTypes)
  {
    cout << "[[ " << type->getTypeName() << " ]]" << endl;
    type->scanForDevices();
    for (const auto &dev : type->getDeviceNames())
    {
      cout << "  - " << dev << endl;
    }
  }
}

void MainApp::playCmd(juce::ArgumentList const &args)
{
  juce::String device = args.getValueForOption("--device|-d");
  uint32_t outputs = args.getValueForOption("--outputs|-o").getIntValue();
  juce::File file = args.getExistingFileForOption("--file|-f");
  uint32_t channel = args.getValueForOption("--channel|-c").getIntValue();

  Engine engine;
  if (auto err =
          engine.configure(Engine::Config().WithDeviceName(device).WithOutputs(outputs));
      err)
    juce::ConsoleApplication::fail(static_cast<juce::String>(err));

  if (auto err = engine.playSound(file, channel); err)
    juce::ConsoleApplication::fail(static_cast<juce::String>(err));
}

void MainApp::runCmd(juce::ArgumentList const &args)
{
  // parse arguments
  uint32_t port = args.getValueForOption("--port|-p").getIntValue();
  uint32_t outputs = args.getValueForOption("--outputs|-o").getIntValue();
  juce::String device = args.getValueForOption("--device|-d");
  port = port != 0 ? port : 60000;  // default port

  // setup chaching
  Cache cache("/Users/lukas/tmp");
  cache.configure();

  // setup aduio engine
  Engine engine;
  if (auto err =
          engine.configure(Engine::Config().WithDeviceName(device).WithOutputs(outputs)))
    juce::ConsoleApplication::fail(static_cast<juce::String>(err));
  try
  {
    asio::io_context ioCtx;
    Server server(ioCtx, port);

    // register callback to play a sample
    server.registerCallback(
        AudioPacket::kPlayMessage,
        [&engine, &cache](std::shared_ptr<AudioPacket> packet)
        {
          if (juce::File::isAbsolutePath(packet->playmessage().uri()))
          {  // is local file
            auto file = juce::File(packet->playmessage().uri());
            if (auto err = engine.playSound(file, packet->playmessage().channel()))
              std::cerr << err << std::endl;
          }
          else if (auto file = cache.get(packet->playmessage().uri()); file.has_value())
          {
            if (auto err = engine.playSound(std::move(file.value()),
                                            packet->playmessage().channel()))
              std::cerr << err << std::endl;
          }
          else
          {
            std::cerr << "not an local or remote file" << std::endl;
          }
        });
    // run the server
    ioCtx.run();
  }
  catch (std::exception &e)
  {
    juce::ConsoleApplication::fail(e.what());
  }
}
