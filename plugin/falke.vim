" falke plugin commands
" Prevent loading twice
if exists('g:loaded_falke')
  finish
endif
let g:loaded_falke = 1

" Command to set the current model
command! -nargs=1 LlmSetModel lua require('falke').set_model(<f-args>)

" Command to list available models
command! LlmListModels lua require('falke').list_models()

" Command to get the current model
command! LlmGetModel lua require('falke').get_current_model()

" Command to refresh the model cache
command! LlmRefreshModels lua require('falke').refresh_models()

" Command to prompt with full file
command! LlmPromptFile lua require('falke').prompt_file()
