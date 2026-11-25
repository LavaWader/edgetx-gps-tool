-- Screen and keys through the EdgeTX API.
local M = {}

-- EdgeTX key event -> the names the core uses, or false.
function M.key(event)
  if event == EVT_VIRTUAL_ENTER then return "enter" end
  if event == EVT_VIRTUAL_EXIT then return "exit" end
  if event == EVT_VIRTUAL_NEXT then return "next" end
  if event == EVT_VIRTUAL_PREV then return "prev" end
  return false
end

-- Execute the core's draw commands (see tool/core/view.lua).
function M.draw(ops)
  lcd.clear()
  for i = 1, #ops do
    local o = ops[i]
    if o.op == "text" then
      local flags = 0 -- INVERS and SMLSIZE are separate bits
      if o.inv then flags = flags + INVERS end
      if o.small then flags = flags + SMLSIZE end
      lcd.drawText(o.x, o.y, o.s, flags)
    else
      lcd.drawFilledRectangle(o.x, o.y, o.w, o.h)
    end
  end
end

return M
