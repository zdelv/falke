local config = require("falke.config")
local models = require("falke.models")
local prompt = require("falke.prompt")
local ui = require("falke.ui")

local M = {}

-- Setup function called by user
function M.setup(opts)
  config.setup(opts)

  -- Auto-fetch models on setup
  models.fetch_models(function(model_list, err)
    if err then
      vim.notify("Failed to fetch models: " .. err, vim.log.levels.WARN)
    end
  end)
end

-- Prompt visual selection (main functionality)
function M.prompt_selection()
  prompt.prompt_visual_selection()
end

-- Prompt full file
function M.prompt_file()
  prompt.prompt_full_file()
end

-- Set the current model
function M.set_model(model_name)
  if not model_name or model_name == "" then
    vim.notify("Model name required", vim.log.levels.ERROR)
    return
  end

  models.set_model(model_name)
end

-- List available models
function M.list_models()
  models.fetch_models(function(model_list, err)
    if err then
      vim.notify("Failed to fetch models: " .. err, vim.log.levels.ERROR)
      return
    end

    local current_model = models.get_current_model()
    ui.show_model_list(model_list, current_model, function(selected_model)
      models.set_model(selected_model)
    end)
  end)
end

-- Get current model
function M.get_current_model()
  local current = models.get_current_model()
  if current then
    vim.notify("Current model: " .. current, vim.log.levels.INFO)
  else
    vim.notify("No model selected", vim.log.levels.WARN)
  end
  return current
end

-- Refresh model cache
function M.refresh_models()
  models.clear_cache()
  models.fetch_models(function(model_list, err)
    if err then
      vim.notify("Failed to refresh models: " .. err, vim.log.levels.ERROR)
      return
    end
    vim.notify("Models refreshed (" .. #model_list .. " models found)", vim.log.levels.INFO)
  end, true)
end

return M
