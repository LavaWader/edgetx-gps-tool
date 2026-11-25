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
      if o.inv then lcd.drawText(o.x, o.y, o.s, INVERS) else lcd.drawText(o.x, o.y, o.s) end
    elseif o.op == "frame" then
      lcd.drawRectangle(o.x, o.y, o.w, o.h)
    elseif o.op == "fill" then
      lcd.drawFilledRectangle(o.x, o.y, o.w, o.h)
    elseif o.op == "rects" then
      local l = o.list
      for k = 1, #l, 4 do lcd.drawFilledRectangle(l[k], l[k + 1], l[k + 2], l[k + 3]) end
    end
  end
end

return M
