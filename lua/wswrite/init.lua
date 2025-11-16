local uv = vim.loop
local M = {}

M.config = { pipe_path = "/tmp/wswrited-pipe" }

function M.setup(cfg)
	M.config = vim.tbl_deep_extend("force", M.config, cfg or {})
end

-- ───────────────── internal state ─────────────────
local fd = nil -- writer fd
local queue = {} -- pending messages
local writing = false -- write in flight?
local opening = false -- currently trying to open?
local dummy_pid = nil -- pid of dummy reader
local open_timer = nil -- uv timer handle
-- --------------------------------------------------

-- helper: start a dummy reader that just holds the pipe open
local function ensure_dummy_reader()
	if dummy_pid then
		return
	end
	dummy_pid = uv.spawn("sh", {
		args = { "-c", string.format("exec < %s &", M.config.pipe_path) },
		stdio = { nil, nil, nil },
	}, function()
		dummy_pid = nil
	end)
end

-- async attempt to open the fifo for write
local function try_open_pipe()
	if fd or opening then
		return
	end
	opening = true
	-- run in thread pool so it can block without freezing UI
	uv.fs_open(M.config.pipe_path, "a", 438, function(err, handle)
		opening = false
		if not err and handle then
			fd = handle
			-- flush anything that queued up
			vim.schedule(function()
				M._flush_queue()
			end)
		else
			-- schedule next attempt
			open_timer:start(500, 0, try_open_pipe) -- try again in 500 ms
		end
	end)
end

-- write next queued msg (must run on main loop)
function M._flush_queue()
	if writing or not fd or #queue == 0 then
		return
	end
	writing = true
	local msg = table.remove(queue, 1) .. "\n"
	uv.fs_write(fd, msg, -1, function(_, err)
		writing = false
		if err then
			vim.schedule(function()
				vim.notify("pipe write error: " .. err, vim.log.levels.WARN)
			end)
			-- drop handle and retry open path
			uv.fs_close(fd)
			fd = nil
			try_open_pipe()
			return
		end
		M._flush_queue() -- keep flushing
	end)
end

-- public write
function M.write(...)
	-- 1. format msg and queue immediately (never blocks)
	local msg = table.concat(
		vim.tbl_map(function(x)
			return x == nil and "nil" or tostring(x)
		end, { ... }),
		"\t"
	)
	queue[#queue + 1] = msg

	-- 2. if we already have fd → flush
	if fd then
		M._flush_queue()
		return
	end

	-- 3. ensure a reader exists, then start/continue open attempts
	ensure_dummy_reader()
	if not open_timer then
		open_timer = uv.new_timer()
		try_open_pipe() -- first immediate attempt
	end
end

-- cleanup (optional)
function M.close_pipe()
	if fd then
		uv.fs_close(fd)
		fd = nil
	end
	if open_timer then
		open_timer:stop()
		open_timer:close()
		open_timer = nil
	end
	if dummy_pid then
		uv.process_kill(dummy_pid, 9)
		dummy_pid = nil
	end
end

-- wrapper with stack trace (unchanged)
function M.log(...)
	local st = {}
	for lvl = 3, math.huge do
		local info = debug.getinfo(lvl, "Sn")
		if not info then
			break
		end
		st[#st + 1] = (info.name or "<unknown>") .. "\r" .. (info.short_src or "<unknown>")
	end
	M.write(table.concat(st, "\t"), ...)
end

return M
