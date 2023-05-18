#pragma once
#include <JuceHeader.h>

#include <map>
#include <string>

class Cache : public juce::URL::DownloadTaskListener
{
  typedef std::shared_ptr<juce::AudioFormatReaderSource> DataType;

 public:
  explicit Cache(std::string const& cachePath) : m_cachePath(juce::File(cachePath)) {}

  Error initialize()
  {
    m_fmtManager.registerBasicFormats();
    if (!m_cachePath.isDirectory())
    {
      if (!m_cachePath.createDirectory()) return Error("could not cre");
    }
    return Error();
  }

  std::optional<DataType> get(std::string const& uri)
  {
    if (m_ressourceMap.contains(uri))
    {
      return m_ressourceMap.at(uri);
    }
    else
    {
      // Todo check if file exists and is the same
      juce::URL url = juce::URL(juce::String(uri));
      auto destination =
          juce::File(m_cachePath.getFullPathName() + "/" + url.getFileName());
      auto task = url.downloadToFile(destination,
                                     juce::URL::DownloadTaskOptions().withListener(this));

      while (!task->isFinished())
      {
        // wait for download
      }
      if (task->hadError())
      {
        return std::nullopt;
      }

      m_ressourceMap[uri] = std::make_shared<juce::AudioFormatReaderSource>(
          m_fmtManager.createReaderFor(destination), true);
      return m_ressourceMap.at(uri);
    }
  }

  void finished(juce::URL::DownloadTask* task, bool success) override
  {
    if (!success)
    {
      std::cerr << "error downloading '";
      std::cerr << task->getTargetLocation().getFullPathName();
      std::cerr << "' status code: " << task->statusCode() << std::endl;
      return;
    }
    else
    {
      std::cout << "Downloaded '" << task->getTargetLocation().getFullPathName() << "'"
                << std::endl;
    }
  }

 private:
  juce::AudioFormatManager m_fmtManager;
  juce::File m_cachePath;
  std::map<std::string, DataType> m_ressourceMap;
};
