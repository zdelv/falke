local M = {}

-- Default configuration
local defaults = {
  endpoint = nil,
  api_key = nil,
  timeout = 30000, -- 30 seconds
  model = nil, -- Will be set from first available model
  stream = false, -- Enable streaming responses
  route_overrides = {},
}

-- Current configuration (merged from setup() and env vars)
M.options = vim.deepcopy(defaults)

-- Setup function called by user in init.lua
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", defaults, opts)
end

-- Get endpoint with fallback to environment variable
function M.get_endpoint()
  if M.options.endpoint then
    return M.options.endpoint
  end

  local env_endpoint = vim.fn.getenv("LLM_ENDPOINT")
  if env_endpoint ~= vim.NIL and env_endpoint ~= "" then
    return env_endpoint
  end

  return nil
end

-- Get API key with fallback to environment variable
function M.get_api_key()
  if M.options.api_key then
    return M.options.api_key
  end

  local env_key = vim.fn.getenv("LLM_API_KEY")
  if env_key ~= vim.NIL and env_key ~= "" then
    return env_key
  end

  return nil
end

function M.get_route_override(route)
  return M.options.route_overrides[route]
end

-- Validate that configuration is complete
function M.validate()
  local endpoint = M.get_endpoint()
  local api_key = M.get_api_key()

  if not endpoint or endpoint == "" then
    return false, "No endpoint configured. Set via setup() or LLM_ENDPOINT env var"
  end

  if not api_key or api_key == "" then
    return false, "No API key configured. Set via setup() or LLM_API_KEY env var"
  end

  return true, nil
end

-- Get current model
function M.get_model()
  return M.options.model
end

-- Set current model
function M.set_model(model)
  M.options.model = model
end

-- Get timeout
function M.get_timeout()
  return M.options.timeout
end

-- Get stream setting
function M.get_stream()
  return M.options.stream
end

return M
