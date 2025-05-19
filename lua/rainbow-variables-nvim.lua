vim.o.termguicolors = true
vim.api.nvim_set_hl(0, '@lsp.type.parameter', {bg = '#002222'})
vim.api.nvim_set_hl(0, '@lsp.type.property', {bg = '#000000'})
vim.api.nvim_set_hl(0, '@lsp.type.variable', {bg = '#000030'})

vim.api.nvim_set_hl(0, 'VarName0', {fg = '#cca650'})
vim.api.nvim_set_hl(0, 'VarName1', {fg = '#50a6fe'})
vim.api.nvim_set_hl(0, 'VarName2', {fg = '#ffa6fe'})
vim.api.nvim_set_hl(0, 'VarName3', {fg = '#ffc66b'})
vim.api.nvim_set_hl(0, 'VarName4', {fg = '#c600ff'})
vim.api.nvim_set_hl(0, 'VarName5', {fg = '#aaffaa'})
vim.api.nvim_set_hl(0, 'VarName6', {fg = '#bbbbbb'})
vim.api.nvim_set_hl(0, 'VarName7', {fg = '#00ff44'})
vim.api.nvim_set_hl(0, 'VarName8', {fg = '#009900'})
vim.api.nvim_set_hl(0, 'VarName9', {fg = '#995500'})
vim.api.nvim_set_hl(0, 'VarName10', {fg = '#3355aa'})
vim.api.nvim_set_hl(0, 'VarName11', {fg = '#009977'})
vim.api.nvim_set_hl(0, 'VarName12', {fg = '#bbbb00'})
vim.api.nvim_set_hl(0, 'VarName13', {fg = '#66ffff'})
vim.api.nvim_set_hl(0, 'VarName14', {fg = '#ff9999'})
vim.api.nvim_set_hl(0, 'VarName15', {fg = '#ffff66'})


function hashToken(token, buf)
	line = vim.api.nvim_buf_get_lines(buf, token.line, token.line + 1, true)[1]
	s = string.sub(line, token.start_col + 1, token.end_col)
	ret = 0
	for i=1,string.len(s),1 do
		ret = ((ret * 27) + string.byte(s,i)) % 16
	end
	return ret
end

vim.api.nvim_create_autocmd("LspTokenUpdate", {
	callback = function(args) 
		local token = args.data.token
		local buf = args.buf
		local client_id = args.data.client_id
		if token.type == "variable" or token.type == "property" or token.type == "parameter" then
			vim.lsp.semantic_tokens.highlight_token(
				token, buf, client_id,
				"VarName" .. hashToken(token, buf)
			)
		end
	end
})

