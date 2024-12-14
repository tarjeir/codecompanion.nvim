local log = require("codecompanion.utils.log")
local message_utils = require("codecompanion.utils.messages")

local perplexity_models = {
  "llama-3.1-sonar-small-128k-online",
  "llama-3.1-sonar-large-128k-online",
  "llama-3.1-sonar-huge-128k-online",
  "llama-3.1-sonar-small-128k-chat",
  "llama-3.1-sonar-large-128k-chat",
  "llama-3.1-8b-instruct",
  "llama-3.1-70b-instruct",
}

---@class Perplexity.Adapter: CodeCompanion.Adapter
return {
  name = "perplexity",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
  },
  features = {
    text = true,
    tokens = true,
    vision = false,
  },
  url = "https://api.perplexity.ai/chat/completions",
  env = {
    api_key = "PERPLEXITY_API_KEY",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  parameters = {
    search_domain_filter = {
      "perplexity.ai",
    },
  },
  handlers = {
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      -- Initialize parameters if they don't exist
      self.parameters = self.parameters or {}
      -- Set required parameters
      local model = self.schema.model.default
      local model_opts = self.schema.model.choices()[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
      end

      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end
      self.parameters.return_citations = true
      self.parameters.return_images = false
      self.parameters.return_related_questions = false
      --self.parameters.search_domain_filter = { "vg.no" }
      self.parameters.search_recency_filter = "month"
      self.parameters.top_k = self.parameters.top_k or 0
      log:debug("Setup parameters: " .. vim.inspect(self.parameters))
      return true
    end,

    ---Set the parameters
    ---@param self CodeCompanion.Adapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      params.model = params.model or self.schema.model.default
      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      messages = message_utils.merge_messages(messages)
      return { messages = messages }
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.Adapter
    ---@param data table The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if json.usage then
            local tokens = json.usage.total_tokens
            log:trace("Tokens: %s", tokens)
            return tokens
          end
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@return table|nil [status: string, output: table]
    chat_output = function(self, data)
      local output = {}

      if data and data ~= "" then
        local data_mod = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if json.choices and #json.choices > 0 then
            local choice = json.choices[1]
            local delta = (self.opts and self.opts.stream) and choice.delta or choice.message

            if delta.content then
              output.content = delta.content
              output.role = delta.role or nil

              return {
                status = "success",
                output = output,
              }
            end
          end
        end
      end
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context table Useful context about the buffer to inline to
    ---@return string|table|nil
    inline_output = function(self, data, context)
      if data and data ~= "" then
        data = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok then
          --- Some third-party OpenAI forwarding services may have a return package with an empty json.choices.
          if not json.choices or #json.choices == 0 then
            return
          end

          local choice = json.choices[1]
          local delta = (self.opts and self.opts.stream) and choice.delta or choice.message
          if delta.content then
            return delta.content
          end
        end
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
      type = "enum",
      default = "llama-3.1-8b-instruct",
      choices = function()
        return perplexity_models
      end,
    },
    temperature = {
      type = "number",
      default = 0.7,
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    max_tokens = {
      type = "integer",
      default = 1024,
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
  },
}
