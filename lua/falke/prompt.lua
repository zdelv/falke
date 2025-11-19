local api = require("falke.api")
local ui = require("falke.ui")
local config = require("falke.config")

local fidget = require("fidget")
local progress = require("fidget.progress")

local M = {}

-- Extract code from LLM response (remove markdown code blocks, explanations)
local function extract_code(response)
  -- Try to find code in markdown code blocks
  -- Pattern 1: ```language\ncode``` or ```\ncode``` (with newline after opening)
  local code = response:match("```%w*\n(.-)```")
  if code then
    return code
  end

  -- Pattern 2: ```language code``` or ``` code``` (without newline after opening)
  code = response:match("```%w*%s*(.-)```")
  if code then
    -- Remove leading/trailing whitespace
    return code:match("^%s*(.-)%s*$")
  end

  -- If no code blocks, return the full response (might be raw code)
  return response
end

-- Get visual selection range and text
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local end_line = end_pos[2]
  local start_col = start_pos[3]
  local end_col = end_pos[3]

  -- Get the selected lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if #lines == 0 then
    return nil, nil, nil
  end

  -- Handle single line selection
  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    -- Handle multi-line selection
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  local selected_text = table.concat(lines, "\n")

  return selected_text, { start_line, start_col }, { end_line, end_col }
end

-- Get the full buffer content
local function get_buffer_content()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, "\n")
end

-- Get file type for context
local function get_filetype()
  return vim.bo.filetype
end

-- Build chat messages for the API
local function build_messages(user_prompt, selected_code, file_content, filetype)
  local system_prompt = string.format(
    [[You are a code editing assistant. The user will provide you with:
1. A prompt describing what they want
2. A selected code block to modify
3. The full file content for context

Your task is to return ONLY the modified code that should replace the selection.
Do not include explanations, markdown formatting, or anything else.
Return only the raw code that will replace the selected block.

File type: %s]],
    filetype or "unknown"
  )

  local user_message = string.format(
    [[Prompt: %s

Selected code to modify:
```
%s
```

Full file content for context:
```
%s
```

Return ONLY the modified code that should replace the selected code block.]],
    user_prompt,
    selected_code,
    file_content
  )

  return {
    { role = "system", content = system_prompt },
    { role = "user", content = user_message },
  }
end

-- Replace visual selection with new code
local function replace_selection(new_code, start_pos, end_pos, buf)
  local start_line, start_col = start_pos[1], start_pos[2]
  local end_line, end_col = end_pos[1], end_pos[2]

  -- Split new code into lines
  local new_lines = vim.split(new_code, "\n", { plain = true })

  -- Get the actual line to ensure end_col is valid
  local line = vim.api.nvim_buf_get_lines(buf, end_line - 1, end_line, false)[1]
  if line then
    -- Clamp end_col to the line length (in bytes)
    -- In visual line mode, end_col can be very large
    end_col = math.min(end_col, #line)
  end

  -- Delete the old selection and insert new code
  -- nvim_buf_set_text uses 0-indexed lines and columns
  -- start_col is inclusive (subtract 1), end_col is exclusive (no subtraction needed)
  vim.api.nvim_buf_set_text(buf, start_line - 1, start_col - 1, end_line - 1, end_col, new_lines)
end

-- Handle streaming response for visual selection
local function handle_streaming_response(messages, start_pos, end_pos, buf)
  local accumulated = ""
  local stream_started = false
  local last_end_line = start_pos[1]
  local last_end_col = start_pos[2]

  local proc = progress.handle.create({
    name = "falke",
    title = "Processing",
    message = "Waiting for LLM to begin streaming...",
  })

  api.chat_completion(messages, function(chunk, err, is_partial)
    if err then
      fidget.notify("Error: " .. err, vim.log.levels.ERROR)
      return
    end

    if chunk then
      -- Handle final complete content vs partial chunks
      if not is_partial then
        -- Final callback with complete content - use it directly
        accumulated = chunk
      else
        -- Partial chunk - accumulate it
        accumulated = accumulated .. chunk
      end

      if not stream_started then
        -- First chunk: clear selection and prepare for streaming
        stream_started = true
        proc:report({
          message = "Reading from stream...",
        })

        -- Clear the selection first by deleting it completely
        local end_line = end_pos[1]
        local end_col = end_pos[2]
        local line = vim.api.nvim_buf_get_lines(buf, end_line - 1, end_line, false)[1]
        if line then
          end_col = math.min(end_col, #line)
        end

        -- Delete the selection - use empty table {} to properly remove all text
        vim.api.nvim_buf_set_text(buf, start_pos[1] - 1, start_pos[2] - 1, end_line - 1, end_col, {})

        -- After clearing, the end position is at the start
        last_end_line = start_pos[1]
        last_end_col = start_pos[2]
      end

      -- Common code for both partial and complete streaming
      local extracted = extract_code(accumulated)
      local lines = vim.split(extracted, "\n", { plain = true })
      vim.api.nvim_buf_set_text(buf, start_pos[1] - 1, start_pos[2] - 1, last_end_line - 1, last_end_col - 1, lines)

      if not is_partial then
        -- Streaming complete
        proc:report({
          message = "Code finished streaming",
          done = true,
        })
        fidget.notify("Code updated successfully", vim.log.levels.INFO)
      else
        -- Still streaming - update the end position for next iteration
        if #lines == 1 then
          last_end_line = start_pos[1]
          last_end_col = start_pos[2] + #lines[1]
        else
          last_end_line = start_pos[1] + #lines - 1
          last_end_col = #lines[#lines] + 1
        end
      end
    end
  end)
end

-- Handle non-streaming response for visual selection
local function handle_non_streaming_response(messages, start_pos, end_pos, buf)
  api.chat_completion(messages, function(response, err)
    if err then
      fidget.notify("Error: " .. err, vim.log.levels.ERROR)
      return
    end

    local proc = progress.handle.create({
      name = "falke",
      title = "Processing",
      message = "Waiting for LLM to return response...",
    })

    -- Extract code from response
    local new_code = extract_code(response)

    -- Replace the selection
    replace_selection(new_code, start_pos, end_pos, buf)

    proc:report({
      message = "Code returned from LLM",
      done = true,
    })
    fidget.notify("Code updated successfully", vim.log.levels.INFO)
  end)
end

-- Main function to handle visual selection prompting
function M.prompt_visual_selection()
  -- Check if we're in visual mode
  local mode = vim.fn.mode()
  local in_visual_mode = (mode == "v" or mode == "V" or mode == "\22")

  if in_visual_mode then
    -- Exit visual mode to update the '< and '> marks with current selection
    -- This is crucial because the marks are only updated when exiting visual mode
    vim.cmd("normal! \27") -- \27 is <Esc>
  else
    -- Not in visual mode, check if we have a previous selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    if start_pos[2] == 0 or end_pos[2] == 0 then
      fidget.notify("No visual selection. Enter visual mode and select code first.", vim.log.levels.WARN)
      return
    end
  end

  -- Get the visual selection (marks are now updated)
  local selected_code, start_pos, end_pos = get_visual_selection()

  if not selected_code then
    fidget.notify("Failed to get visual selection", vim.log.levels.ERROR)
    return
  end

  -- Get file context
  local file_content = get_buffer_content()
  local filetype = get_filetype()

  local buf = vim.api.nvim_get_current_buf()

  -- Show input prompt
  ui.show_prompt_input(function(user_prompt)
    if not user_prompt or user_prompt == "" then
      fidget.notify("No prompt provided", vim.log.levels.WARN)
      return
    end

    -- Build messages
    local messages = build_messages(user_prompt, selected_code, file_content, filetype)

    -- Check if streaming is enabled
    local is_streaming = config.get_stream()

    if is_streaming then
      handle_streaming_response(messages, start_pos, end_pos, buf)
    else
      handle_non_streaming_response(messages, start_pos, end_pos, buf)
    end
  end)
end

-- Build chat messages for full file editing
local function build_file_messages(user_prompt, file_content, filetype)
  local is_empty = file_content == "" or file_content:match("^%s*$")

  local system_prompt
  if is_empty then
    system_prompt = string.format(
      [[You are a code generation assistant. The user will provide a prompt describing what code they want.
The file is currently empty, so you will generate new code from scratch.

Your task is to return ONLY the complete code for the file.
Do not include explanations, markdown formatting, or anything else.
Return only the raw code.

File type: %s]],
      filetype or "unknown"
    )
  else
    system_prompt = string.format(
      [[You are a code editing assistant. The user will provide you with:
1. A prompt describing what they want
2. The complete current file content

Your task is to return ONLY the complete modified file content.
Do not include explanations, markdown formatting, or anything else.
Return only the raw code for the entire file.

File type: %s]],
      filetype or "unknown"
    )
  end

  local user_message
  if is_empty then
    user_message = string.format(
      [[Prompt: %s

Generate the complete file content based on this prompt.]],
      user_prompt
    )
  else
    user_message = string.format(
      [[Prompt: %s

Current file content:
```
%s
```

Return the complete modified file content.]],
      user_prompt,
      file_content
    )
  end

  return {
    { role = "system", content = system_prompt },
    { role = "user", content = user_message },
  }
end

-- Replace entire file with new content
local function replace_file(new_content, buf)
  -- Split new content into lines
  local new_lines = vim.split(new_content, "\n", { plain = true })

  -- Get current line count
  local line_count = vim.api.nvim_buf_line_count(buf)

  -- Replace all lines in the buffer
  vim.api.nvim_buf_set_lines(buf, 0, line_count, false, new_lines)
end

-- Handle streaming response for full file
local function handle_streaming_file_response(messages, buf)
  local accumulated = ""
  local stream_started = false

  local proc = progress.handle.create({
    name = "falke",
    title = "Processing",
    message = "Waiting for LLM to begin streaming...",
  })

  api.chat_completion(messages, function(chunk, err, is_partial)
    if err then
      fidget.notify("Error: " .. err, vim.log.levels.ERROR)
      proc:cancel()
      return
    end

    if chunk then
      -- Handle final complete content vs partial chunks
      if not is_partial then
        -- Final callback with complete content - use it directly
        accumulated = chunk
      else
        -- Partial chunk - accumulate it
        accumulated = accumulated .. chunk
      end

      if not stream_started then
        -- First chunk: clear file and prepare for streaming
        stream_started = true
        proc:report({
          message = "Reading from stream...",
        })

        -- Clear the entire file
        local line_count = vim.api.nvim_buf_line_count(0)
        vim.api.nvim_buf_set_lines(buf, 0, line_count, false, { "" })
      end

      local extracted = extract_code(accumulated)
      local lines = vim.split(extracted, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      if not is_partial then
        proc:report({
          message = "Code finished streaming",
          done = true,
        })
        fidget.notify("File updated successfully", vim.log.levels.INFO)
      end
    end
  end)
end

-- Handle non-streaming response for full file
local function handle_non_streaming_file_response(messages, buf)
  api.chat_completion(messages, function(response, err)
    local proc = progress.handle.create({
      name = "falke",
      title = "Processing",
      message = "Waiting for LLM to return response...",
    })

    if err then
      fidget.notify("Error: " .. err, vim.log.levels.ERROR)
      proc:cancel()
      return
    end

    -- Extract code from response
    local new_content = extract_code(response)

    -- Replace the entire file
    replace_file(new_content, buf)

    proc:report({
      message = "Code returned from LLM",
      done = true,
    })
    fidget.notify("File updated successfully", vim.log.levels.INFO)
  end)
end

-- Main function to handle full file prompting
function M.prompt_full_file()
  -- Get file content and context
  local file_content = get_buffer_content()
  local filetype = get_filetype()

  local buf = vim.api.nvim_get_current_buf()

  -- Show input prompt
  ui.show_prompt_input(function(user_prompt)
    if not user_prompt or user_prompt == "" then
      fidget.notify("No prompt provided", vim.log.levels.WARN)
      return
    end

    -- Build messages
    local messages = build_file_messages(user_prompt, file_content, filetype)

    -- Check if streaming is enabled
    local is_streaming = config.get_stream()

    if is_streaming then
      handle_streaming_file_response(messages, buf)
    else
      handle_non_streaming_file_response(messages, buf)
    end
  end)
end

return M
