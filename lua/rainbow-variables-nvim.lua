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

local block_node_names = {["chunk"] = true, ["block"] = true, ["compound_statement"] = true}

local function get_node_statement(node)
	while node:parent() ~= nil and not block_node_names[node:parent():type()] do
		node = node:parent()
	end
	return node
end

local declaration_node_names = {["local_declaration"] = true, ["variable_decration"] = true, ["declaration"] = true}

local function get_previous_declaration(statement_node)
	repeat
		local prev = statement_node:prev_sibling()
		if prev == nil then
			local parent = statement_node:parent()
			if parent == nil then
				return nil
			end
			local statement_parent = get_node_statement(parent)
			if statement_parent == nil then
				return nil
			end
			return get_previous_declaration(statement_parent)
		end
		statement_node = prev
	until declaration_node_names[statement_node:type()]
	return statement_node
end

local declarator_recursion_ends = {["identifier"] = true}

local function declared_variables(declaration_node, buf)
	local result = {}
	local declarators = declaration_node:field("declarator")
	for _, d in pairs(declarators) do
		if declarator_recursion_ends[d:type()] then
			local line_number, start_col, _ = d:start()
			local _, end_col, _ = d:end_()
			local line = vim.api.nvim_buf_get_lines(buf, line_number, line_number + 1, true)[1]
			local varname = string.sub(line, start_col + 1, end_col)
			result[varname] = true
		else
			for varname, _ in pairs(declared_variables(d, buf)) do
				result[varname] = true
			end
		end
	end
	return result
end

local function declared_variables_dbg(declaration_node, buf)
	local result = ""
	for i, _ in pairs(declared_variables(declaration_node, buf)) do
		result = result .. "(" .. i .. ") "
	end
	return result
end

local function get_declaration_statement_of_variable(node, varname, buf)
	local statement_node = get_node_statement(node)
	if statement_node == nil then
		return nil
	end
	if declaration_node_names[statement_node:type()] and declared_variables(statement_node, buf)[varname] then
		return statement_node
	end
	local declaration_node = get_previous_declaration(statement_node)
	while not (declaration_node == nil or declared_variables(declaration_node, buf)[varname]) do
		declaration_node = get_previous_declaration(declaration_node)
	end
	return declaration_node
end

local function get_declaration_statement_dbg(node, varname, buf)
	local declaration_node = get_declaration_statement_of_variable(node, varname, buf)
	if declaration_node == nil then
		return "no declaration found"
	end
	local line_number, start_col, _ = declaration_node:start()
	local _, end_col, _ = declaration_node:end_()
	local line = vim.api.nvim_buf_get_lines(buf, line_number, line_number + 1, true)[1]
	return string.sub(line, start_col + 1, end_col)
end

local function get_scope_hash(node, varname, buf) 
	local result = 15
	local declaration_node = get_declaration_statement_of_variable(node, varname, buf)
	if declaration_node == nil then
		return result
	end
	while declaration_node ~= nil do
		if block_node_names[declaration_node:type()] then
			result = result + 1
		end
		declaration_node = declaration_node:parent()
	end
	return result
end

local function hash_token(token, buf, use_scope_hash)
	local node = vim.treesitter.get_node({bufnr = buf, pos = {token.line, token.start_col}})
	local line = vim.api.nvim_buf_get_lines(buf, token.line, token.line + 1, true)[1]
	local varname = string.sub(line, token.start_col + 1, token.end_col)
	-- print(node, node:parent(), node:type(), varname, get_scope_hash(node, varname, buf))
	local ret = 0
	for i=1,string.len(varname),1 do
		ret = ((ret * 27) + string.byte(varname,i)) % 16
	end
	if use_scope_hash then
		return (ret + get_scope_hash(node, varname, buf)) % 16
	end
	return ret
end

vim.api.nvim_create_autocmd("LspTokenUpdate", {
	callback = function(args)
		local token = args.data.token
		local buf = args.buf
		local client_id = args.data.client_id
		if token.type == "property" or token.type == "parameter" or token.type == "class" then
			vim.lsp.semantic_tokens.highlight_token(
				token, buf, client_id,
				"VarName" .. hash_token(token, buf, false)
			)
		elseif token.type == "variable" then
			vim.lsp.semantic_tokens.highlight_token(
				token, buf, client_id,
				"VarName" .. hash_token(token, buf, true)
			)
		end
	end
})

