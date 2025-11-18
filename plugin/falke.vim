" falke plugin commands
" Prevent loading twice
if exists('g:loaded_falke')
  finish
endif
let g:loaded_falke = 1

" Command to set the current model
command! -nargs=1 FalkeSetModel lua require('falke').set_model(<f-args>)

" Command to list available models
command! FalkeListModels lua require('falke').list_models()

" Command to get the current model
command! FalkeGetModel lua require('falke').get_current_model()

" Command to refresh the model cache
command! FalkeRefreshModels lua require('falke').refresh_models()

" Command to prompt with full file
command! FalkePromptFile lua require('falke').prompt_file()

" Get and Set temperature
command! -nargs=1 FalkeSetTemp lua require('falke').set_temperature(<f-args>)
command! FalkeGetTemp lua require('falke').get_temperature()
