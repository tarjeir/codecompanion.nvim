---Source:
---https://github.com/google-gemini/cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb

local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.messages")

---@class Gemini.Adapter: CodeCompanion.Adapter
return {
  name = "gemini",
  roles = {
    llm = "model",
    user = "user",
  },
  opts = {
    stream = true, -- NOTE: Currently, CodeCompanion ONLY supports streaming with this adapter
  },
  features = {
    tokens = true,
    text = true,
    vision = true,
  },
  url = "https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${api_key}",
  env = {
    api_key = "GEMINI_API_KEY",
    model = "schema.model.default",
  },
  headers = {
    ["Content-Type"] = "application/json",
  },
  handlers = {
    ---Set the parameters
    ---@param self CodeCompanion.Adapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param messages table Format is: { contents = { parts { text = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      -- Format system prompts
      local system = utils.pluck_messages(vim.deepcopy(messages), "system")
      local system_instruction

      -- Only create system_instruction if there are system messages
      if #system > 0 then
        for _, msg in ipairs(system) do
          msg.text = msg.content

          -- Remove unnecessary fields
          msg.tag = nil
          msg.content = nil
          msg.role = nil
          msg.id = nil
          msg.opts = nil
        end
        system_instruction = {
          role = self.roles.user,
          parts = system,
        }
      end

      -- Format messages (remove all system prompts)
      local output = {}
      local user = utils.pop_messages(vim.deepcopy(messages), "system")
      for _, msg in ipairs(user) do
        table.insert(output, {
          role = self.roles.user,
          parts = {
            { text = msg.content },
          },
        })
      end

      -- Only include system_instruction if it exists
      local result = {
        contents = output,
      }
      if system_instruction then
        result.system_instruction = system_instruction
      end

      return result
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.Adapter
    ---@param data string The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data and data ~= "" then
        data = data:sub(6)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok then
          return json.usageMetadata.totalTokenCount
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data string The streamed JSON data from the API, also formatted by the format_data handler
    ---@return table|nil
    chat_output = function(self, data)
      local output = {}

      if data and data ~= "" then
        data = data:sub(6)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok and json.candidates[1].content then
          output.role = "llm"
          output.content = json.candidates[1].content.parts[1].text

          return {
            status = "success",
            output = output,
          }
        end
      end
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context table Useful context about the buffer to inline to
    ---@return table|nil
    inline_output = function(self, data, context)
      if data and data ~= "" then
        data = data:sub(6)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          return
        end

        return json.candidates[1].content.parts[1].text
      end
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.Adapter
    ---@param data table
    ---@return nil
    on_exit = function(self, data)
      if data.status >= 400 then
        log:error("Error: %s", data.body)
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      type = "enum",
      desc = "The model that will complete your prompt. See https://ai.google.dev/gemini-api/docs/models/gemini#model-variations for additional details and options.",
      default = "gemini-1.5-flash",
      choices = {
        "gemini-1.5-flash",
        "gemini-1.5-pro",
        "gemini-1.0-pro",
      },
    },
  },
}
