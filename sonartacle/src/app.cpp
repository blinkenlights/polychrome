#include "app.h"

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

        MultiChannelSampler sampler(m_deviceManager, device, outputs);
        if (auto err = sampler.initialize(); err) fail(static_cast<juce::String>(err));

        if (auto err = sampler.playSound(file, channel); err)
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

        MultiChannelSampler sampler(m_deviceManager, "MacBook Pro Speakers", 2);
        if (auto err = sampler.initialize())
          juce::ConsoleApplication::fail(static_cast<juce::String>(err));
        try
        {
          asio::io_context ioCtx;
          Server server(ioCtx, port);
          server.registerCallback(
              AudioPacket::kPlayMessage,
              [&sampler](std::shared_ptr<AudioPacket> packet)
              {
                std::cout << "play message: " << std::endl;
                std::cout << "uri: " << packet->playmessage().uri() << " ";
                std::cout << "start: " << packet->playmessage().start();
                std::cout << std::endl;
                juce::File file(packet->playmessage().uri());
                if (!file.existsAsFile())
                {
                  std::cerr << "file '" << file.getFullPathName() << "' does not exist"
                            << std::endl;
                  return;
                }
                if (auto err = sampler.playSound(file, packet->playmessage().channel()))
                  juce::ConsoleApplication::fail(static_cast<juce::String>(err));
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

/* --------------------------- MutliChannelSampler -------------------------- */

/**
 * @brief Construct a new Multi Channel Sampler:: Multi Channel Sampler object
 *
 * @param devMngr pointer to the device manager
 * @param deviceName name of the device we want to use
 * @param outputs number of outputs
 */
MultiChannelSampler::MultiChannelSampler(shared_ptr<juce::AudioDeviceManager> devMngr,
                                         juce::String const &deviceName, int outputs) :
  m_deviceManager(devMngr),
  m_mainProcessor(new juce::AudioProcessorGraph()),
  m_player(new juce::AudioProcessorPlayer()),
  m_outputs(outputs),
  m_sampleRate(48000),
  m_deviceName(deviceName)
{
}

MultiChannelSampler::~MultiChannelSampler()
{
  m_deviceManager->removeAudioCallback(m_player.get());
  m_mainProcessor->releaseResources();
}

/**
 * @brief Initializes the audio engine which is a AudioGraph.
 *
 */
Error MultiChannelSampler::initializeEngine()
{
  auto device = m_deviceManager->getCurrentAudioDevice();
  auto sampleRate = device->getCurrentSampleRate();
  auto samplesPerBlock = device->getCurrentBufferSizeSamples();

  if (!m_mainProcessor->enableAllBuses()) return Error("could not enable buses");
  m_mainProcessor->setPlayConfigDetails(0, m_outputs, sampleRate, samplesPerBlock);
  m_mainProcessor->prepareToPlay(sampleRate, samplesPerBlock);

  m_mainProcessor->clear();
  audioOutputNode = m_mainProcessor->addNode(
      make_unique<AudioGraphIOProcessor>(AudioGraphIOProcessor::audioOutputNode));
  if (!audioOutputNode) return Error("could not add output node");
  m_player->setProcessor(m_mainProcessor.get());
  m_deviceManager->addAudioCallback(m_player.get());
  return Error();
}

/**
 * @brief Initializes the device manager with number of outputs and sample rate.
 *
 */
Error MultiChannelSampler::initializeDeviceManager()
{
  auto setup = m_deviceManager->getAudioDeviceSetup();
  setup.outputDeviceName = m_deviceName;
  setup.outputChannels = m_outputs;
  setup.inputChannels = m_outputs;
  setup.sampleRate = m_sampleRate;

  auto err = m_deviceManager->initialise(m_outputs, m_outputs, nullptr, true, "", &setup);
  if (err.isNotEmpty())
  {
    return Error("initializing deviceManager: " + err);
  }
  return Error();
}

/**
 * @brief Initializes the device manager and the audio engine
 *
 */
Error MultiChannelSampler::initialize()
{
  if (auto err = initializeDeviceManager()) return err;
  if (auto err = initializeEngine()) return err;
  return Error();
}

/**
 * @brief Plays back a single file
 *
 * @param file
 * @param channel
 */
Error MultiChannelSampler::playSound(juce::File const &file, int channel)
{
  cout << "Playing " << file.getFullPathName() << " on channel " << channel << endl;
  Error err;
  auto node = m_mainProcessor->addNode(make_unique<MonoFilePlayerProcessor>(file));
  auto conn = Connection{{node->nodeID, 0}, {audioOutputNode->nodeID, channel - 1}};
  m_mainProcessor->addConnection(conn);
  if (auto proc = dynamic_cast<MonoFilePlayerProcessor *>(node->getProcessor()))
  {
    proc->start();
  }
  else
  {
    err = Error("not a MonoFilePlayerProcessor");
  }
  return err;
}
