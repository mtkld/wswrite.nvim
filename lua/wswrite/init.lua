local M = {}

-- Default configuration
M.config = {
	-- You have to manually create the named pipe, mkfifo /tmp/websocket-pipe
	pipe_path = "/tmp/wswrited-pipe", -- Default pipe path
}

-- Setup function to configure the plugin
function M.setup(config)
	-- Merge user config with default config
	M.config = vim.tbl_deep_extend("force", M.config, config or {})
end

-- The wrapper function log
function M.log(...)
	local args = { ... }

	-- Initialize the log_args table
	local log_args = {}

	-- Initialize a table to collect stack trace
	local stack_trace = {}

	-- Loop through the call stack, starting from level 2 (the immediate caller)
	local level = 2
	while true do
		local info = debug.getinfo(level, "Sn") -- 'S' for source (module), 'n' for function name
		if not info then
			break -- No more stack frames
		end

		-- Get the function name, use "<unknown>" if not available
		local func_name = info.name or "<unknown>"

		-- Get the source (module or file), use "<unknown>" if not available
		local source = info.short_src or "<unknown>"

		-- Format as "funcName{path}"
		local formatted_entry = func_name .. "\r" .. source

		-- Add the formatted entry to the stack trace
		table.insert(stack_trace, formatted_entry)

		level = level + 1 -- Move up to the next level in the call stack
	end

	-- Reverse the stack trace to have it from the root to the current function
	for i = #stack_trace, 1, -1 do
		table.insert(log_args, stack_trace[i])
	end

	-- Append original arguments to the log_args table
	for i = 1, select("#", ...) do
		table.insert(log_args, select(i, ...))
	end

	-- Call the write function with the modified arguments
	M.write(unpack(log_args))
end

-- Function to write to the named pipe
function M.write(...)
	local args = { ... }
	local arg_count = #args

	-- Check if at least one argument is given
	if arg_count < 1 then
		print("Error: At least one argument is required.")
		return
	end

	-- Determine if there is only one argument (use as message without category)
	local message, category
	if arg_count == 1 then
		message = args[1]
		category = nil
	else
		-- Multiple arguments: last one is the message, others form the category
		message = args[arg_count]
		category = table.concat(vim.list_slice(args, 1, arg_count - 1), "\t")
	end

	-- Open the pipe in append mode
	local file = io.open(M.config.pipe_path, "a")

	-- Check if the pipe was opened successfully
	if not file then
		print("Error: Could not open pipe at " .. M.config.pipe_path)
		return
	end

	-- Format the message, add category if present
	local formatted_message
	if category then
		formatted_message = category .. "\t" .. message
	else
		formatted_message = message
	end

	-- Write the formatted message to the pipe
	file:write(formatted_message .. "\n")
	file:close()

	-- Echo the formatted message in Neovim
	--print("Sent to pipe: " .. formatted_message)
end

return M
