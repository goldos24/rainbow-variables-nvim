local M = {}

local block_node_names = {["chunk"] = true, ["block"] = true, ["compound_statement"] = true}

local function get_node_statement(node)
	while node:parent() ~= nil and not block_node_names[node:parent():type()] do
		node = node:parent()
	end
	return node
end

local declaration_node_names = {["local_declaration"] = true, ["variable_declaration"] = true, ["declaration"] = true}

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

local lua_declarator_boilerplate_nodes = {["local_declaration"] = true, ["assignment_statement"] = true, ["variable_declaration"] = true}
local lua_declarator_nodes = {["local_declaration"] = true, ["variable_declaration"] = true}

local function declared_variables_lua(declaration_node, buf)
	while lua_declarator_boilerplate_nodes[declaration_node:type()] do
		declaration_node = declaration_node:child(0)
	end
	local name_nodes = declaration_node:field("name")
	local result = {}
	for _, d in pairs(name_nodes) do
		local line_number, start_col, _ = d:start()
		local _, end_col, _ = d:end_()
		local line = vim.api.nvim_buf_get_lines(buf, line_number, line_number + 1, true)[1]
		local varname = string.sub(line, start_col + 1, end_col)
		result[varname] = true
	end
	return result
end

local function declared_variables(declaration_node, buf)
	if lua_declarator_nodes[declaration_node:type()] then
		return declared_variables_lua(declaration_node, buf)
	end
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

local color_usage_count = {}

for i=1, 16, 1 do
	color_usage_count[i] = 0
end

local ids_by_variable = {}

local function hash_token(token, buf, scope_shadowing, reduce_color_collisions, color_count)
	local line = vim.api.nvim_buf_get_lines(buf, token.line, token.line + 1, true)[1]
	local varname = string.sub(line, token.start_col + 1, token.end_col)
	-- print(node, node:parent(), node:type(), varname, get_scope_hash(node, varname, buf))
	local ret = 0
	local factor = 27
	for i=1,string.len(varname),1 do
		ret = ((ret * factor) + string.byte(varname,i)) % color_count
	end
	-- 'multilevel' is borked if you use the insert mode at any point in time
	if scope_shadowing == 'multilevel' then
		local node = vim.treesitter.get_node({bufnr = buf, pos = {token.line, token.start_col}})
		local declaration_statement = get_declaration_statement_of_variable(node, varname, buf)
		if declaration_statement ~= nil then
			_, declaration_statement = declaration_statement:end_()
		end
		ret = (ret + get_scope_hash(node, varname, buf)) % color_count
	elseif scope_shadowing == 'members' and token.type == "property" then
		ret = (ret + 1) % color_count
	end
	if ids_by_variable[varname] ~= nil then
		return ids_by_variable[varname]
	else
		if reduce_color_collisions then
			local min = color_usage_count[ret+1]
			local min_index = ret+1
			for i=ret+1,ret+19, 3 do
				local index = (i-1) % color_count + 1
				local count = color_usage_count[index]
				if count < min then
					min = count
					min_index = index
				end
			end
			ret = min_index - 1
		end
		ids_by_variable[varname] = ret
		color_usage_count[ret+1] = color_usage_count[ret+1] + 1
	end
	return ret
end

local function set_color_palette(colors)
	local color_count = 0
	for _, color in pairs(colors) do
		vim.api.nvim_set_hl(0, 'VarName' .. color_count, {fg = color})
		color_count = color_count + 1
	end
	return color_count
end

function M.start_with_config(config)
	vim.o.termguicolors = true
	if config.semantic_background_colors == nil or config.semantic_background_colors then
		vim.api.nvim_set_hl(0, '@lsp.type.parameter', {bg = '#002222'})
		vim.api.nvim_set_hl(0, '@lsp.type.property', {bg = '#000000'})
		vim.api.nvim_set_hl(0, '@lsp.type.variable', {bg = '#000030'})
	end
	local reduce_color_collisions = false
	if config.reduce_color_collisions ~= nil then
		reduce_color_collisions = config.reduce_color_collisions
	end
	local palette = {
		'#cca650',
		'#50a6fe',
		'#ffa6fe',
		'#ffc66b',
		'#c600ff',
		'#aaffaa',
		'#bbbbbb',
		'#00ff44',
		'#009900',
		'#995500',
		'#3355aa',
		'#009977',
		'#bbbb00',
		'#66ffff',
		'#ff9999',
		'#ffff66',
	}
	if config.palette ~= nil then
		palette = config.palette
	end
	local color_count = set_color_palette(palette)
	vim.api.nvim_create_autocmd("LspTokenUpdate", {
		callback = function(args)
			local token = args.data.token
			local buf = args.buf
			local client_id = args.data.client_id
			if token.type == "property" or token.type == "parameter" or token.type == "class" then
				vim.lsp.semantic_tokens.highlight_token(
					token, buf, client_id,
					"VarName" .. hash_token(token, buf, config.scope_shadowing, reduce_color_collisions, color_count)
				)
			elseif token.type == "variable" then
				vim.lsp.semantic_tokens.highlight_token(
					token, buf, client_id,
					"VarName" .. hash_token(token, buf, config.scope_shadowing, reduce_color_collisions, color_count)
				)
			end
		end
	})
end

return M
