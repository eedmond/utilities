local M = {}

local CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

local function png_path(job)
	local cache = ya.file_cache(job)
	if not cache then return nil end

	local p = tostring(cache)
	if p:find("^file://") then p = p:sub(8) end

	-- Embed source file mtime so cache auto-invalidates on edit
	local stat = Command("stat"):arg("-f"):arg("%m"):arg(tostring(job.file.path)):output()
	local mtime = stat and stat.stdout:match("%d+") or "0"

	return p .. "_" .. mtime .. ".png"
end

function M:peek(job)
	local path = png_path(job)
	if not path then return require("code"):peek(job) end

	-- Cache hit
	local f = io.open(path, "rb")
	if f then
		f:close()
		local _, err = ya.image_show(Url(path), job.area)
		if not err then return end
	end

	-- Render with Chrome (blocks until done; peek returns with final image)
	local out = Command(CHROME)
		:arg("--headless=new")
		:arg("--no-sandbox")
		:arg("--disable-gpu")
		:arg("--allow-file-access-from-files")
		:arg("--screenshot=" .. path)
		:arg("--window-size=1200,900")
		:arg("file://" .. tostring(job.file.path))
		:output()

	if not out or out.status.code ~= 0 then
		return require("code"):peek(job)
	end

	local _, err = ya.image_show(Url(path), job.area)
	if err then return require("code"):peek(job) end
end

function M:seek(job) end

return M
