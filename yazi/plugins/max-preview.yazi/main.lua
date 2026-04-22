local set_state = ya.sync(function(s, maximized, w, x, y, max_w, max_h)
	s.maximized = maximized
	rt.mgr.ratio = { w, x, y }
	rt.preview.max_width = max_w
	rt.preview.max_height = max_h
end)

local get_max = ya.sync(function(s) return s.maximized or false end)

return {
	entry = function()
		if get_max() then
			set_state(false, 1, 4, 3, 1200, 900)
		else
			set_state(true, 0, 0, 1, 3000, 3000)
		end
		ya.mgr_emit("arrow", { 1 })
		ya.mgr_emit("arrow", { -1 })
	end,
}
