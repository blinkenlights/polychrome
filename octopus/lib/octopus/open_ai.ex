defmodule Octopus.OpenAi do
  # @callback

  defp system_prompt(length_in_words \\ 50) do
    "This GPT is designed to create short, entertaining, and somewhat magical stories from a young person's first-person perspective." <>
      "The gender of the narrator is unspecified and should remain ambiguous." <>
      "The story is set outdoors and may include other characters." <>
      "Each story is aimed to be around #{length_in_words} words in length, with a humorous twist at the end." <>
      "Use short sentences. Give the whole story a dadaist style and make the plot slightly crazy but funny."
  end

  defp generate(system_prompt) do
    OpenAI.chat_completion(
      model: "gpt-3.5-turbo",
      messages: [
        %{role: "system", content: system_prompt()},
        %{role: "user", content: "Schreibe eine Geschichte"}
      ],
      temperature: 1.0,
      max_tokens: 256,
      frequency_penalty: 0.0,
      presence_penalty: 0.0
    )
  end
end
