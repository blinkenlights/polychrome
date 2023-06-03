#include "app.h"

#include "engine.h"
#include "resource.h"
#include "server.h"

namespace beak
{
/**
 * @brief Construct a new Main App:: Main App object
 *
 */
MainApp::MainApp() : Thread("beak"), m_deviceManager(new juce::AudioDeviceManager())
{
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
      "server",
      "server",
      "Starts the udp server",
      "This command runs a udp server with an protobuf api.",
      serverCmd,
  });
}

/**
 * @brief Destroy the Main App:: Main App object
 *
 */
MainApp::~MainApp()
{
  juce::MessageManager::deleteInstance();
  juce::DeletedAtShutdown::deleteAll();
}

/**
 * @brief Reimplemented to initialise JUCEApplication
 *
 * @param args
 */
void MainApp::initialise(const juce::String &args)
{
  m_args = args;
  startThread();
}

/**
 * @brief Reimplemented to shutdown the JUCEApplication
 *
 */
void MainApp::shutdown()
{
  std::cout << "shutting down..." << std::endl;
  signalThreadShouldExit();
}

/**
 * @brief Reimplemented to run the thread for the main app
 *
 * Run the command in a seperate thread, because the event loop will be run in the main thread.
 *
 */
void MainApp::run() { findAndRunCommand(juce::ArgumentList("beak", m_args), false); }

/* -------------------------------- commands -------------------------------- */

/**
 * @brief Command to list the available devices
 *
 */
void MainApp::listCmd(juce::ArgumentList const & /*args*/)
{
  juce::OwnedArray<juce::AudioIODeviceType> devTypes;
  juce::AudioDeviceManager deviceManager;
  deviceManager.createAudioDeviceTypes(devTypes);
  for (const auto &type : devTypes)
  {
    std::cout << "[[ " << type->getTypeName() << " ]]" << std::endl;
    type->scanForDevices();
    for (const auto &dev : type->getDeviceNames())
    {
      std::cout << "  - " << dev << std::endl;
    }
  }
  juce::JUCEApplication::getInstance()->systemRequestedQuit();
}

/**
 * @brief Command to play one sample
 *
 * @param args Command line arguments
 */
void MainApp::playCmd(juce::ArgumentList const &args)
{
  juce::String const device = args.getValueForOption("--device|-d");
  int const outputs = args.getValueForOption("--outputs|-o").getIntValue();
  juce::File const file = args.getExistingFileForOption("--file|-f");
  int const channel = args.getValueForOption("--channel|-c").getIntValue();

  Engine engine;
  if (auto err = engine.configure(Engine::Config().WithDeviceName(device).WithOutputs(outputs));
      err)
  {
    juce::ConsoleApplication::fail(static_cast<juce::String>(err));
  }

  if (auto err = engine.playSound(file, channel); err)
  {
    juce::ConsoleApplication::fail(static_cast<juce::String>(err));
  }
}

/**
 * @brief Command to run the udp server
 *
 * @param args Command line arguments
 */
void MainApp::serverCmd(juce::ArgumentList const &args)
{
  // parse arguments
  uint32_t port = args.getValueForOption("--port|-p").getIntValue();
  int const outputs = args.getValueForOption("--outputs|-o").getIntValue();
  int const inputs = args.getValueForOption("--inputs|-i").getIntValue();
  juce::String const device = args.getValueForOption("--device|-d");
  juce::String cacheDir = args.getValueForOption("--cache|-c");
  port = port != 0 ? port : defaultPort;  // default port
  cacheDir = cacheDir.isEmpty() ? "/home/gueldi/tmp" : cacheDir;
  // setup chaching
  Cache cache(cacheDir);
  if (auto err = cache.configure())
  {
    juce::ConsoleApplication::fail(err.what());
  }

  // setup aduio engine
  Engine engine;
  if (auto err = engine.configure(Engine::Config()
                                      .WithDeviceName(device)
                                      .WithInputs(inputs)
                                      .WithOutputs(outputs)
                                      .WithSampleRate(Engine::Config::defaultSampleRate)))
  {
    juce::ConsoleApplication::fail(static_cast<juce::String>(err));
  }
  try
  {
    asio::io_context ioCtx;
    net::Server server(ioCtx, port);

    // register callback to play a sample
    server.registerCallback(
        Packet::kAudioFrame,
        [&engine, &cache](std::shared_ptr<Packet> packet)
        {
          auto uri = packet->audio_frame().uri();
          auto channel = static_cast<int>(packet->audio_frame().channel());
          if (auto [file, err] = cache.get(uri); !err)
          {
            if (auto err = engine.playSound(std::move(file.value()), channel, uri))
            {
              std::cerr << err << std::endl;
            }
          }
          else
          {
            std::cerr << err.what() << std::endl;
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
}  // namespace beak

/**
 *
 * Start the JUCEApplication, int main() is here.
 */
START_JUCE_APPLICATION(beak::MainApp)
