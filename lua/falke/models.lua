local api = require("falke.api")
local config = require("falke.config")

local M = {}

-- Cache for fetched models
M.cached_models = nil

-- Fetch models and cache the result
function M.fetch_models(callback, force_refresh)
  -- Return cached models if available and not forcing refresh
  if M.cached_models and not force_refresh then
    callback(M.cached_models, nil)
    return
  end

  api.get_models(function(models, err)
    if err then
      callback(nil, err)
      return
    end

    -- Cache the models
    M.cached_models = models

    -- If no model is currently selected and we have models, select the first one
    if not config.get_model() and models and #models > 0 then
      config.set_model(models[1])
      vim.notify("Auto-selected model: " .. models[1], vim.log.levels.INFO)
    end

    callback(models, nil)
  end)
end

-- Set the current model
function M.set_model(model_name)
  -- Validate that the model exists in our cached list
  if M.cached_models then
    local found = false
    for _, model in ipairs(M.cached_models) do
      if model == model_name then
        found = true
        break
      end
    end

    if not found then
      vim.notify("Warning: Model '" .. model_name .. "' not in cached list", vim.log.levels.WARN)
    end
  end

  config.set_model(model_name)
  vim.notify("Model set to: " .. model_name, vim.log.levels.INFO)
end

-- Get the current model
function M.get_current_model()
  return config.get_model()
end

-- Clear the model cache
function M.clear_cache()
  M.cached_models = nil
end

return M
