local notifier = require 'notifier'
local notify = notifier.notify
local vt_evs = notifier.vt

function vt_monitor (event, c, vc_num)
	if event == vt_evs.VT_WRITE then
		print (string.format("Write event: c=%d, vc_num=%d", c, vc_num))
	end
	return notify.OK end
end

notifier.vterm (vt_monitor)
