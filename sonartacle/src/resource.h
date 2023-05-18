#pragma once
#include <map>
#include <string>

class Cache : public juce::URL::DownloadTaskListener
{
  typedef std::unique_ptr<juce::AudioFormatReaderSource> CacheDataType;
  typedef std::unique_ptr<juce::File> InternalDataType;

 public:
  explicit Cache(std::string const& cachePath) : m_cachePath(juce::File(cachePath)) {}

  Error configure()
  {
    if (!m_cachePath.isDirectory())
    {
      if (!m_cachePath.createDirectory()) return Error("could not cre");
    }
    return Error();
  }

  std::optional<juce::File> get(std::string const& uri)
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
      if (task->hadError() || task->statusCode() != 200)
      {
        return std::nullopt;
      }

      m_ressourceMap[uri] = destination;
      return destination;
    }
  }

  void progress(juce::URL::DownloadTask* /*task*/, int64 bytesDownloaded,
                int64 totalLength) override
  {
    double progress = bytesDownloaded / totalLength;
    int barWidth = 70;

    std::cout << "[";
    int pos = barWidth * progress;
    for (int i = 0; i < barWidth; ++i)
    {
      if (i < pos)
        std::cout << "=";
      else if (i == pos)
        std::cout << ">";
      else
        std::cout << " ";
    }
    std::cout << "] " << int(progress * 100.0) << " %\r";
    std::cout.flush();

    if (progress >= 1.0) std::cout << std::endl;
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
  juce::File m_cachePath;
  std::map<std::string, juce::File> m_ressourceMap;
};
