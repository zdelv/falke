local M = {}

-- Create a centered floating window
local function create_floating_window(width, height, title)
  -- Calculate position to center the window
  local ui = vim.api.nvim_list_uis()[1]
  local win_width = math.floor(width)
  local win_height = math.floor(height)
  local row = math.floor((ui.height - win_height) / 2)
  local col = math.floor((ui.width - win_width) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "falke", { buf = buf })

  -- Window options
  local opts = {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  }

  -- Only set title and title_pos if title is provided
  if title then
    opts.title = " " .. title .. " "
    opts.title_pos = "center"
  end

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_set_option_value("winblend", 0, { win = win })

  return buf, win
end

-- Show a floating input window and call callback with user input
function M.show_prompt_input(callback)
  local width = 70
  local height = 8
  local buf, win = create_floating_window(width, height, "Enter Prompt (Ctrl+Enter to submit)")

  -- Set buffer options
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  -- Set window options for wrapping
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })

  -- Enter insert mode
  vim.cmd("startinsert")

  -- Map keys to handle input
  local function close_and_submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    -- Filter out empty lines at the end
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end

    local input = table.concat(lines, "\n")

    -- Close window
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end

    -- Call callback with input
    if input and input ~= "" then
      callback(input)
    end
  end

  local function close_and_cancel()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Set up keymaps
  -- Ctrl+Enter to submit from insert mode
  vim.keymap.set("i", "<C-CR>", close_and_submit, { buffer = buf, nowait = true })
  -- Escape to cancel
  vim.keymap.set("i", "<Esc>", close_and_cancel, { buffer = buf, nowait = true })
  -- Normal mode: Enter to submit
  vim.keymap.set("n", "<CR>", close_and_submit, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_and_cancel, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", close_and_cancel, { buffer = buf, nowait = true })
end

-- Show a model selection list
function M.show_model_list(models, current_model, on_select)
  if not models or #models == 0 then
    fidget.notify("No models available", vim.log.levels.WARN)
    return
  end

  local width = 50
  local height = math.min(#models + 2, 20)
  local buf, win = create_floating_window(width, height, "Select Model")

  -- Set buffer as modifiable to add content
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

  -- Add models to buffer and track current model position
  local lines = { "Select a model (press Enter):", "" }
  local current_line = nil
  for i, model in ipairs(models) do
    local prefix = "  "
    if current_model and model == current_model then
      prefix = "→ "
      current_line = i + 2  -- +2 for header and blank line
    end
    table.insert(lines, prefix .. model)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Make buffer read-only
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Move cursor to current model if found, otherwise first model (line 3)
  local initial_line = current_line or 3
  vim.api.nvim_win_set_cursor(win, { initial_line, 0 })

  -- Handle selection
  local function select_model()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_num = cursor[1]

    -- Line 1 is header, line 2 is blank, models start at line 3
    if line_num >= 3 and line_num < 3 + #models then
      local selected_model = models[line_num - 2]

      -- Close window
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end

      -- Call callback
      on_select(selected_model)
    end
  end

  local function close_window()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Set up keymaps
  vim.keymap.set("n", "<CR>", select_model, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_window, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", close_window, { buffer = buf, nowait = true })
  vim.keymap.set("n", "j", "j", { buffer = buf, nowait = true })
  vim.keymap.set("n", "k", "k", { buffer = buf, nowait = true })
end

-- Show a loading indicator
function M.show_loading(message)
  message = message or "Processing..."

  local width = #message + 4
  local height = 1
  local buf, win = create_floating_window(width, height, nil)

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  return win
end

-- Close a window
function M.close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

return M
