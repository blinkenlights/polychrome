#include "app.h"

#include <plog/Log.h>

#include "engine.h"
#include "plog/Formatters/TxtFormatter.h"
#include "plog/Initializers/ConsoleInitializer.h"
#include "resource.h"
#include "server.h"
#include "simEngine.h"

namespace beak
{
/**
 * @brief Construct a new Main App:: Main App object
 *
 */
MainApp::MainApp() : Thread("beak")
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
  static plog::ColorConsoleAppender<plog::TxtFormatter> consoleAppender;
  plog::init(plog::debug, &consoleAppender);
  PLOGI << "Starting " << getApplicationName() << "v" << getApplicationVersion();
  m_args = args;
  startThread();
}

/**
 * @brief Reimplemented to shutdown the JUCEApplication
 *
 */
void MainApp::shutdown()
{
  PLOGI << "shutting down...";
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
    PLOGF << err.what();
    std::terminate();
  }

  if (auto err = engine.playSound(file, channel); err)
  {
    PLOGF << err.what();
    std::terminate();
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
  bool isSimulation = args.containsOption("--sim|-s");
  port = port != 0 ? port : defaultPort;  // default port
  cacheDir = cacheDir.isEmpty() ? "/tmp/beak" : cacheDir;
  // setup chaching
  Cache cache(cacheDir);
  if (auto err = cache.configure())
  {
    PLOGF << err.what();
    std::terminate();
  }

  // setup aduio engine
  std::unique_ptr<Engine> engine;
  if (isSimulation)
  {
    engine.reset(new sim::SimulationEngine(outputs));
    if (auto err = engine->configure(Engine::Config()
                                         .WithDeviceName(device)
                                         .WithInputs(inputs)
                                         .WithOutputs(2)
                                         .WithSampleRate(Engine::Config::defaultSampleRate)))
    {
      PLOGF << err.what();
      std::terminate();
    }
  }
  else
  {
    engine.reset(new Engine());

    if (auto err = engine->configure(Engine::Config()
                                         .WithDeviceName(device)
                                         .WithInputs(inputs)
                                         .WithOutputs(outputs)
                                         .WithSampleRate(Engine::Config::defaultSampleRate)))
    {
      PLOGF << err.what();
      std::terminate();
    }
  }
  try
  {
    asio::io_context ioCtx;
    net::Server server(ioCtx, port);

    // register callback to play a sample
    server.registerCallback(Packet::kAudioFrame,
                            [&engine, &cache](std::shared_ptr<Packet> packet)
                            {
                              auto uri = packet->audio_frame().uri();
                              auto channel = static_cast<int>(packet->audio_frame().channel());
                              if (auto [file, err] = cache.get(uri); !err)
                              {
                                if (auto err = engine->playSound(file.value(), channel))
                                {
                                  PLOGE << err.what();
                                }
                              }
                              else
                              {
                                PLOGE << err.what();
                              }
                            });
    // run the server
    ioCtx.run();
  }
  catch (std::exception &e)
  {
    PLOGF << e.what();
    std::terminate();
  }
}
}  // namespace beak

/**
 *
 * Start the JUCEApplication, int main() is here.
 */
START_JUCE_APPLICATION(beak::MainApp)
