local ltn12 = require "ltn12"

function get_receiver(msg)
  if msg.to.type == 'user' then
    return 'user#id'..msg.from.id
  end
  if msg.to.type == 'chat' then
    return 'chat#id'..msg.to.id
  end
end

function is_chat_msg( msg )
  if msg.to.type == 'chat' then
    return true
  end
  return false
end

function string.random(length)
   local str = "";
   for i = 1, length do
      math.random(97, 122)
      str = str..string.char(math.random(97, 122));
   end
   return str;
end

function string:split(sep)
  local sep, fields = sep or ":", {}
  local pattern = string.format("([^%s]+)", sep)
  self:gsub(pattern, function(c) fields[#fields+1] = c end)
  return fields
end

-- Removes spaces
function string.trim(s)
  return s:gsub("^%s*(.-)%s*$", "%1")
end

--  Saves file to /tmp/. If file_name isn't provided, 
-- will get the text after the last "/" for filename.
function download_to_file(url, file_name)
  print("url to download: "..url)

  local respbody = {}
  local options = {
    url = url,
    sink = ltn12.sink.table(respbody),
    redirect = true
  }

  local one, c, h = http.request(options)
  
  -- Everything after the last /
  local file_name = url:match("([^/]+)$") 
  local file_path = "/tmp/"..file_name

  file = io.open(file_path, "w+")
  file:write(table.concat(respbody))
  file:close()

  return file_path
end


function vardump(value, depth, key)
  local linePrefix = ""
  local spaces = ""
  
  if key ~= nil then
    linePrefix = "["..key.."] = "
  end
  
  if depth == nil then
    depth = 0
  else
    depth = depth + 1
    for i=1, depth do spaces = spaces .. "  " end
  end
  
  if type(value) == 'table' then
    mTable = getmetatable(value)
    if mTable == nil then
      print(spaces ..linePrefix.."(table) ")
    else
      print(spaces .."(metatable) ")
        value = mTable
    end		
    for tableKey, tableValue in pairs(value) do
      vardump(tableValue, depth, tableKey)
    end
  elseif type(value)	== 'function' or 
      type(value)	== 'thread' or 
      type(value)	== 'userdata' or
      value		== nil
  then
    print(spaces..tostring(value))
  else
    print(spaces..linePrefix.."("..type(value)..") "..tostring(value))
  end
end

-- taken from http://stackoverflow.com/a/11130774/3163199
function scandir(directory)
  local i, t, popen = 0, {}, io.popen
  for filename in popen('ls -a "'..directory..'"'):lines() do
      i = i + 1
      t[i] = filename
  end
  return t
end

-- http://www.lua.org/manual/5.2/manual.html#pdf-io.popen
function run_command(str)
  local cmd = io.popen(str)
  local result = cmd:read('*all')
  cmd:close()
  return result
end

function is_sudo(msg)
   local var = false
   -- Check users id in config 
   for v,user in pairs(_config.sudo_users) do 
      if user == msg.from.id then 
         var = true 
      end
   end
   return var
end

-- Returns the name of the sender
function get_name(msg)
   local name = msg.from.first_name
   if name == nil then
      name = msg.from.id
   end
   return name
end

-- Returns at table of lua files inside plugins
function plugins_names( )
  local files = {}
  for k, v in pairs(scandir("plugins")) do
    -- Ends with .lua
    if (v:match(".lua$")) then
      table.insert(files, v)
    end 
  end
  return files
end

-- Function name explains what it does.
function file_exists(name)
  local f = io.open(name,"r")
  if f ~= nil then 
    io.close(f) 
    return true 
  else 
    return false 
  end
end

-- Save into file the data serialized for lua.
function serialize_to_file(data, file)
  file = io.open(file, 'w+')
  local serialized = serpent.block(data, {
    comment = false,
    name = "_"
  })
  file:write(serialized)
  file:close()
end

-- Retruns true if the string is empty
function string:isempty()
  return self == nil or self == ''
end

-- Returns true if String starts with Start
function string.starts(String, Start)
   return Start == string.sub(String,1,string.len(Start))
end

-- Send image to user and delete it when finished.
-- cb_function and cb_extra are optionals callback
function _send_photo(receiver, file_path, cb_function, cb_extra)
  local cb_extra = {
    file_path = file_path,
    cb_function = cb_function,
    cb_extra = cb_extra
  }
  -- Call to remove with optional callback
  send_photo(receiver, file_path, rmtmp_cb, cb_extra)
end

-- Download the image and send to receiver, it will be deleted.
function send_photo_from_url(receiver, url)
  local file_path = download_to_file(url, false)
  print("File path: "..file_path)
  _send_photo(receiver, file_path)
end

--  Send multimple images asynchronous.
-- param urls must be a table.
function send_photos_from_url(receiver, urls)
  local cb_extra = {
    receiver = receiver,
    urls = urls,
    remove_path = nil
  }
  send_photos_from_url_callback(cb_extra)
end

-- Use send_photos_from_url. 
-- This fuction might be difficult to understand.
function send_photos_from_url_callback(cb_extra, success, result)
  -- cb_extra is a table containing receiver, urls and remove_path
  local receiver = cb_extra.receiver
  local urls = cb_extra.urls
  local remove_path = cb_extra.remove_path

  -- The previously image to remove
  if remove_path ~= nil then
    os.remove(remove_path)
    print("Deleted: "..remove_path)
  end

  -- Nil or empty, exit case (no more urls)
  if urls == nil or #urls == 0 then
    return false
  end

  -- Take the head and remove from urls table
  local head = table.remove(urls, 1)

  local file_path = download_to_file(head, false)
  local cb_extra = {
    receiver = receiver,
    urls = urls,
    remove_path = file_path
  }

  -- Send first and postpone the others as callback
  send_photo(receiver, file_path, send_photos_from_url_callback, cb_extra)
end

-- Callback to remove a file
function rmtmp_cb(cb_extra, success, result)
  local file_path = cb_extra.file_path
  local cb_function = cb_extra.cb_function
  local cb_extra = cb_extra.cb_extra

  if file_path ~= nil then
    os.remove(file_path)
    print("Deleted: "..file_path)
  end
  -- Finaly call the callback
  cb_function(cb_extra, success, result)
end

-- Send document to user and delete it when finished.
-- cb_function and cb_extra are optionals callback
function _send_document(receiver, file_path, cb_function, cb_extra)
  local cb_extra = {
    file_path = file_path,
    cb_function = cb_function or ok_cb,
    cb_extra = cb_extra or false
  }
  -- Call to remove with optional callback
  send_document(receiver, file_path, rmtmp_cb, cb_extra)
end

-- Download the image and send to receiver, it will be deleted.
-- cb_function and cb_extra are optionals callback
function send_document_from_url(receiver, url, cb_function, cb_extra)
  local file_path = download_to_file(url, false)
  print("File path: "..file_path)
  _send_document(receiver, file_path, cb_function, cb_extra)
end