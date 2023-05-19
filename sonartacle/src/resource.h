#pragma once
#include <JuceHeader.h>

#include <map>
#include <optional>
#include <sstream>
#include <string>

#include "error.h"

class Cache : public juce::URL::DownloadTaskListener
{
  typedef std::unique_ptr<juce::AudioFormatReaderSource> CacheDataType;
  typedef std::unique_ptr<juce::File> InternalDataType;

 public:
  explicit Cache(juce::String const& cachePath) : m_cachePath(juce::File(cachePath)) {}

  [[nodiscard]] Error configure()
  {
    if (!m_cachePath.isDirectory())
    {
      if (auto res = m_cachePath.createDirectory(); res.failed())
        return Error("could not create cache directory");
    }
    return Error();
  }

  [[nodiscard]] std::tuple<std::optional<juce::File>, Error> get(std::string const& uri)
  {
    if (m_ressourceMap.contains(uri))
    {
      return std::make_tuple(m_ressourceMap.at(uri), Error());
    }
    else
    {
      // Todo check if file exists and is the same
      juce::URL url = juce::URL(juce::String(uri));
      if (!url.isWellFormed())
      {
        return std::make_tuple(std::nullopt, Error("url is malformed"));
      }
      auto destination =
          juce::File(m_cachePath.getFullPathName() + "/" + url.getFileName());
      std::unique_ptr<juce::URL::DownloadTask> task = url.downloadToFile(
          destination, juce::URL::DownloadTaskOptions().withListener(this));
      if (!task)
      {
        return std::make_tuple(std::nullopt,
                               Error("unable to download " + url.toString(false)));
      }
      while (task && !task->isFinished())
      {
        // wait for download
      }
      if (task->hadError() || task->statusCode() != 200)
      {
        std::stringstream err;
        err << "download failed, status: " << task->statusCode();
        return std::make_tuple(std::nullopt, Error(err.str()));
      }

      m_ressourceMap[uri] = destination;
      return std::make_tuple(destination, Error());
    }
  }

  void progress(juce::URL::DownloadTask* /*task*/, int64 bytesDownloaded,
                int64 totalLength) override
  {
    double progress =
        static_cast<double>(bytesDownloaded) / static_cast<double>(totalLength);
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
