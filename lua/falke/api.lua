local config = require("falke.config")

local M = {}

-- Base curl executor with custom handlers
-- handlers: { on_stdout(data), on_stderr(data), on_exit(code, stdout, stderr) }
local function execute_curl_base(args, handlers)
  local stdout_data = {}
  local stderr_data = {}

  local handle = vim.system(args, {
    stdout = function(_, data)
      if data then
        if handlers.on_stdout then
          handlers.on_stdout(data)
        end
        table.insert(stdout_data, data)
      end
    end,
    stderr = function(_, data)
      if data then
        if handlers.on_stderr then
          handlers.on_stderr(data)
        end
        table.insert(stderr_data, data)
      end
    end,
  }, function(result)
    vim.schedule(function()
      local stdout = table.concat(stdout_data, "")
      local stderr = table.concat(stderr_data, "")
      handlers.on_exit(result.code, stdout, stderr)
    end)
  end)

  return handle
end

-- Execute curl and parse JSON response (for simple GET/POST requests)
local function execute_curl_json(args, callback)
  return execute_curl_base(args, {
    on_exit = function(code, stdout, stderr)
      if code ~= 0 then
        callback(nil, "curl failed: " .. stderr)
        return
      end

      -- Parse JSON response
      local ok, json = pcall(vim.json.decode, stdout)
      if not ok then
        callback(nil, "Failed to parse JSON response: " .. json)
        return
      end

      callback(json, nil)
    end,
  })
end

-- Fetch available models from /v1/models endpoint
function M.get_models(callback)
  local ok, err = config.validate()
  if not ok then
    callback(nil, err)
    return
  end

  local endpoint = config.get_endpoint()
  local api_key = config.get_api_key()
  local url = endpoint .. "/v1/models"

  local args = {
    "curl",
    "-s",
    "-X",
    "GET",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-H",
    "Content-Type: application/json",
    "--max-time",
    tostring(math.floor(config.get_timeout() / 1000)),
    url,
  }

  execute_curl_json(args, function(json, error)
    if error then
      callback(nil, error)
      return
    end

    -- Extract model IDs from response
    if json.data and type(json.data) == "table" then
      local models = {}
      for _, model in ipairs(json.data) do
        if model.id then
          table.insert(models, model.id)
        end
      end
      callback(models, nil)
    else
      callback(nil, "Invalid models response format")
    end
  end)
end

-- Parse SSE (Server-Sent Events) line and extract content
local function parse_sse_line(line)
  -- SSE format: "data: {json}"
  if line:match("^data: %[DONE%]") then
    return nil, true -- Signal completion
  end

  local json_str = line:match("^data: (.+)$")
  if not json_str then
    return nil, false
  end

  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, false
  end

  -- Extract content from delta
  if data.choices and data.choices[1] and data.choices[1].delta then
    local delta = data.choices[1].delta
    if delta.content and type(delta.content) == "string" then
      return delta.content, false
    end
  end

  return nil, false
end

-- Execute curl with SSE streaming support
local function execute_curl_stream(args, callback)
  local buffer = ""
  local full_content = ""
  local stream_completed = false

  return execute_curl_base(args, {
    on_stdout = function(data)
      buffer = buffer .. data

      -- Process complete lines
      while true do
        local newline_pos = buffer:find("\n")
        if not newline_pos then
          break
        end

        local line = buffer:sub(1, newline_pos - 1)
        buffer = buffer:sub(newline_pos + 1)

        -- Parse SSE line
        local content, done = parse_sse_line(line)
        if done then
          -- Streaming complete, send full content
          stream_completed = true
          callback(full_content, nil)
          return
        elseif content and type(content) == "string" then
          full_content = full_content .. content
          -- Send chunk to callback (true = partial/streaming)
          callback(content, nil, true)
        end
      end
    end,
    on_stderr = function(data)
      callback(nil, "Stream error: " .. data)
    end,
    on_exit = function(code, stdout, stderr)
      if code ~= 0 then
        callback(nil, "curl failed with code " .. code)
      elseif not stream_completed and full_content ~= "" then
        -- Stream ended without [DONE] message, send final callback
        callback(full_content, nil)
      end
    end,
  })
end

-- Validate configuration and model selection
local function validate_chat_config()
  local ok, err = config.validate()
  if not ok then
    return nil, err
  end

  local model = config.get_model()
  if not model then
    return nil, "No model selected. Use :LlmSetModel to select a model"
  end

  return model
end

-- Build curl arguments for chat completion
local function build_chat_args(model, messages)
  local use_stream = config.get_stream()
  local endpoint = config.get_endpoint()
  local api_key = config.get_api_key()
  local url = endpoint .. "/v1/chat/completions"

  local payload = vim.json.encode({
    model = model,
    messages = messages,
    temperature = 0.7,
    stream = use_stream,
  })

  return {
    "curl",
    "-s",
    "-N", -- Disable buffering for streaming
    "-X",
    "POST",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-H",
    "Content-Type: application/json",
    "--max-time",
    tostring(math.floor(config.get_timeout() / 1000)),
    "-d",
    payload,
    url,
  },
    use_stream
end

-- Extract content from chat completion JSON response
local function extract_chat_content(json)
  if json.choices and json.choices[1] and json.choices[1].message then
    return json.choices[1].message.content, nil
  elseif json.error then
    local error_msg = json.error.message or vim.inspect(json.error)
    return nil, "API error: " .. error_msg
  else
    return nil, "Invalid chat completion response format"
  end
end

-- Send chat completion request with streaming support
function M.chat_completion(messages, callback)
  local model, err = validate_chat_config()
  if not model then
    callback(nil, err)
    return
  end

  local args, use_stream = build_chat_args(model, messages)

  if use_stream then
    return execute_curl_stream(args, callback)
  else
    return execute_curl_json(args, function(json, error)
      if error then
        callback(nil, error)
        return
      end

      local content, extract_err = extract_chat_content(json)
      callback(content, extract_err)
    end)
  end
end

return M
